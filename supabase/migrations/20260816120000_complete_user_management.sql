-- UniMIS User Management completion (corrected)
-- Fix: preserve existing institution_user_directory column order and append email at the end.

alter table public.profiles
  add column if not exists email text;

update public.profiles p
set email = lower(u.email)
from auth.users u
where u.id = p.id
  and (p.email is null or lower(p.email) is distinct from lower(u.email));

create index if not exists idx_profiles_email
  on public.profiles(lower(email));

create or replace function public.accept_own_user_invitation()
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_email text;
  v_invitation_id uuid;
  v_updated integer;
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

  select
    lower(email),
    nullif(raw_user_meta_data ->> 'invitation_id', '')::uuid
  into
    v_email,
    v_invitation_id
  from auth.users
  where id = v_uid;

  if v_email is null then
    return false;
  end if;

  if v_invitation_id is not null then
    update public.user_invitations
    set
      status = 'accepted',
      accepted_at = coalesce(accepted_at, now()),
      updated_at = now()
    where id = v_invitation_id
      and lower(email) = v_email
      and status = 'pending';

    get diagnostics v_updated = row_count;

    if v_updated > 0 then
      return true;
    end if;
  end if;

  update public.user_invitations ui
  set
    status = 'accepted',
    accepted_at = coalesce(ui.accepted_at, now()),
    updated_at = now()
  where lower(ui.email) = v_email
    and ui.status = 'pending'
    and exists (
      select 1
      from public.institution_users iu
      where iu.user_id = v_uid
        and iu.institution_id = ui.institution_id
    );

  get diagnostics v_updated = row_count;
  return v_updated > 0;
end;
$$;

revoke all on function public.accept_own_user_invitation() from public;
grant execute on function public.accept_own_user_invitation() to authenticated;

-- IMPORTANT:
-- CREATE OR REPLACE VIEW cannot insert a new column in the middle because
-- PostgreSQL interprets that as renaming existing columns.
-- Preserve the original column order and append email LAST.
create or replace view public.institution_user_directory
with (security_invoker=true)
as
select
  iu.id as institution_user_id,
  iu.institution_id,
  iu.user_id,
  p.first_name,
  p.middle_name,
  p.last_name,
  p.display_name,
  p.phone,
  p.avatar_url,
  iu.staff_number,
  iu.student_number,
  iu.role_id,
  r.code as role_code,
  r.name as role_name,
  iu.status,
  iu.is_primary,
  iu.joined_at,
  iu.created_at,
  p.email
from public.institution_users iu
left join public.profiles p on p.id = iu.user_id
left join public.roles r on r.id = iu.role_id;

grant select on public.institution_user_directory to authenticated;

create or replace function public.handle_unimis_invited_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_institution_id uuid;
  v_role_id uuid;
  v_first_name text;
  v_middle_name text;
  v_last_name text;
  v_staff_number text;
  v_student_number text;
  v_display_name text;
begin
  if new.raw_user_meta_data is null
     or nullif(new.raw_user_meta_data ->> 'institution_id', '') is null
     or nullif(new.raw_user_meta_data ->> 'role_id', '') is null then
    return new;
  end if;

  v_institution_id := (new.raw_user_meta_data ->> 'institution_id')::uuid;
  v_role_id := (new.raw_user_meta_data ->> 'role_id')::uuid;
  v_first_name := nullif(trim(new.raw_user_meta_data ->> 'first_name'), '');
  v_middle_name := nullif(trim(new.raw_user_meta_data ->> 'middle_name'), '');
  v_last_name := nullif(trim(new.raw_user_meta_data ->> 'last_name'), '');
  v_staff_number := nullif(trim(new.raw_user_meta_data ->> 'staff_number'), '');
  v_student_number := nullif(trim(new.raw_user_meta_data ->> 'student_number'), '');
  v_display_name := nullif(trim(concat_ws(' ', v_first_name, v_last_name)), '');

  if v_display_name is null then
    v_display_name := new.email;
  end if;

  if not exists (
    select 1 from public.institutions i where i.id = v_institution_id
  ) then
    raise exception 'Invalid UniMIS institution in auth metadata';
  end if;

  if not exists (
    select 1
    from public.roles r
    where r.id = v_role_id
      and r.is_active = true
      and (r.institution_id is null or r.institution_id = v_institution_id)
  ) then
    raise exception 'Invalid UniMIS role in auth metadata';
  end if;

  insert into public.profiles (
    id, email, first_name, middle_name, last_name, display_name, status
  )
  values (
    new.id, lower(new.email), v_first_name, v_middle_name,
    v_last_name, v_display_name, 'active'
  )
  on conflict (id)
  do update set
    email = excluded.email,
    first_name = excluded.first_name,
    middle_name = excluded.middle_name,
    last_name = excluded.last_name,
    display_name = excluded.display_name,
    status = 'active',
    updated_at = now();

  if exists (
    select 1
    from public.institution_users iu
    where iu.institution_id = v_institution_id
      and iu.user_id = new.id
  ) then
    update public.institution_users
    set
      role_id = v_role_id,
      staff_number = coalesce(v_staff_number, staff_number),
      student_number = coalesce(v_student_number, student_number),
      status = 'active'
    where institution_id = v_institution_id
      and user_id = new.id;
  else
    insert into public.institution_users (
      institution_id, user_id, role_id, staff_number,
      student_number, status, is_primary
    )
    values (
      v_institution_id, new.id, v_role_id, v_staff_number,
      v_student_number, 'active', true
    );
  end if;

  return new;
end;
$$;

notify pgrst, 'reload schema';
