-- ============================================================
-- UniMIS
-- AUTH INVITE BOOTSTRAP
--
-- Purpose:
-- When Supabase Auth creates an invited user, automatically create:
--   1. public.profiles
--   2. public.institution_users
--
-- The Edge Function sends these values in raw_user_meta_data:
-- first_name, middle_name, last_name, institution_id, role_id,
-- invitation_id, staff_number, student_number.
-- ============================================================

create or replace function public.handle_unimis_invited_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_institution_id uuid;
  v_role_id uuid;
  v_invitation_id uuid;
  v_first_name text;
  v_middle_name text;
  v_last_name text;
  v_staff_number text;
  v_student_number text;
  v_display_name text;
begin
  -- Only bootstrap users that came through the UniMIS invitation flow.
  if new.raw_user_meta_data is null
     or nullif(new.raw_user_meta_data ->> 'institution_id', '') is null
     or nullif(new.raw_user_meta_data ->> 'role_id', '') is null then
    return new;
  end if;

  v_institution_id :=
    (new.raw_user_meta_data ->> 'institution_id')::uuid;

  v_role_id :=
    (new.raw_user_meta_data ->> 'role_id')::uuid;

  v_invitation_id :=
    nullif(
      new.raw_user_meta_data ->> 'invitation_id',
      ''
    )::uuid;

  v_first_name :=
    nullif(
      trim(new.raw_user_meta_data ->> 'first_name'),
      ''
    );

  v_middle_name :=
    nullif(
      trim(new.raw_user_meta_data ->> 'middle_name'),
      ''
    );

  v_last_name :=
    nullif(
      trim(new.raw_user_meta_data ->> 'last_name'),
      ''
    );

  v_staff_number :=
    nullif(
      trim(new.raw_user_meta_data ->> 'staff_number'),
      ''
    );

  v_student_number :=
    nullif(
      trim(new.raw_user_meta_data ->> 'student_number'),
      ''
    );

  v_display_name :=
    nullif(
      trim(
        concat_ws(
          ' ',
          v_first_name,
          v_last_name
        )
      ),
      ''
    );

  if v_display_name is null then
    v_display_name := new.email;
  end if;

  -- Validate the referenced institution.
  if not exists (
    select 1
    from public.institutions i
    where i.id = v_institution_id
  ) then
    raise exception
      'Invalid UniMIS institution in auth metadata';
  end if;

  -- Validate the referenced active role.
  if not exists (
    select 1
    from public.roles r
    where r.id = v_role_id
      and r.is_active = true
      and (
        r.institution_id is null
        or r.institution_id = v_institution_id
      )
  ) then
    raise exception
      'Invalid UniMIS role in auth metadata';
  end if;

  insert into public.profiles (
    id,
    first_name,
    middle_name,
    last_name,
    display_name,
    status
  )
  values (
    new.id,
    v_first_name,
    v_middle_name,
    v_last_name,
    v_display_name,
    'active'
  )
  on conflict (id)
  do update set
    first_name = excluded.first_name,
    middle_name = excluded.middle_name,
    last_name = excluded.last_name,
    display_name = excluded.display_name,
    status = 'active',
    updated_at = now();

  insert into public.institution_users (
    institution_id,
    user_id,
    role_id,
    staff_number,
    student_number,
    status,
    is_primary
  )
  values (
    v_institution_id,
    new.id,
    v_role_id,
    v_staff_number,
    v_student_number,
    'active',
    true
  )
  on conflict do nothing;

  -- If a membership already existed, make sure the invitation's values win.
  update public.institution_users
  set
    role_id = v_role_id,
    staff_number = coalesce(
      v_staff_number,
      staff_number
    ),
    student_number = coalesce(
      v_student_number,
      student_number
    ),
    status = 'active'
  where institution_id = v_institution_id
    and user_id = new.id;

  -- Keep the invitation pending until the invite is actually accepted.
  if v_invitation_id is not null then
    update public.user_invitations
    set
      updated_at = now()
    where id = v_invitation_id;
  end if;

  return new;
end;
$$;


-- Remove only our named trigger if rerunning this migration in development.
drop trigger if exists
  on_unimis_invited_auth_user
on auth.users;

create trigger on_unimis_invited_auth_user
after insert
on auth.users
for each row
execute function public.handle_unimis_invited_auth_user();


-- Helper for already-created Auth users that missed bootstrap before this fix.
create or replace function public.repair_unimis_invited_user(
  p_email text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user auth.users%rowtype;
begin
  select *
  into v_user
  from auth.users
  where lower(email) = lower(trim(p_email))
  limit 1;

  if v_user.id is null then
    raise exception 'Auth user not found';
  end if;

  perform public.handle_unimis_invited_auth_user_row(v_user);
end;
$$;

-- PostgreSQL cannot directly call a trigger function with a row argument.
-- Replace the repair function above with a self-contained implementation.
drop function if exists public.repair_unimis_invited_user(text);

create or replace function public.repair_unimis_invited_user(
  p_email text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_email text;
  v_meta jsonb;
  v_institution_id uuid;
  v_role_id uuid;
  v_invitation_id uuid;
  v_first_name text;
  v_middle_name text;
  v_last_name text;
  v_staff_number text;
  v_student_number text;
  v_display_name text;
begin
  select
    id,
    email,
    raw_user_meta_data
  into
    v_user_id,
    v_email,
    v_meta
  from auth.users
  where lower(email) = lower(trim(p_email))
  limit 1;

  if v_user_id is null then
    raise exception 'Auth user not found';
  end if;

  if v_meta is null
     or nullif(v_meta ->> 'institution_id', '') is null
     or nullif(v_meta ->> 'role_id', '') is null then
    raise exception
      'Auth user does not contain UniMIS invitation metadata';
  end if;

  v_institution_id :=
    (v_meta ->> 'institution_id')::uuid;

  v_role_id :=
    (v_meta ->> 'role_id')::uuid;

  v_invitation_id :=
    nullif(v_meta ->> 'invitation_id', '')::uuid;

  v_first_name :=
    nullif(trim(v_meta ->> 'first_name'), '');

  v_middle_name :=
    nullif(trim(v_meta ->> 'middle_name'), '');

  v_last_name :=
    nullif(trim(v_meta ->> 'last_name'), '');

  v_staff_number :=
    nullif(trim(v_meta ->> 'staff_number'), '');

  v_student_number :=
    nullif(trim(v_meta ->> 'student_number'), '');

  v_display_name :=
    nullif(
      trim(
        concat_ws(
          ' ',
          v_first_name,
          v_last_name
        )
      ),
      ''
    );

  if v_display_name is null then
    v_display_name := v_email;
  end if;

  insert into public.profiles (
    id,
    first_name,
    middle_name,
    last_name,
    display_name,
    status
  )
  values (
    v_user_id,
    v_first_name,
    v_middle_name,
    v_last_name,
    v_display_name,
    'active'
  )
  on conflict (id)
  do update set
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
      and iu.user_id = v_user_id
  ) then
    update public.institution_users
    set
      role_id = v_role_id,
      staff_number = coalesce(
        v_staff_number,
        staff_number
      ),
      student_number = coalesce(
        v_student_number,
        student_number
      ),
      status = 'active'
    where institution_id = v_institution_id
      and user_id = v_user_id;
  else
    insert into public.institution_users (
      institution_id,
      user_id,
      role_id,
      staff_number,
      student_number,
      status,
      is_primary
    )
    values (
      v_institution_id,
      v_user_id,
      v_role_id,
      v_staff_number,
      v_student_number,
      'active',
      true
    );
  end if;

  if v_invitation_id is not null then
    update public.user_invitations
    set updated_at = now()
    where id = v_invitation_id;
  end if;
end;
$$;

revoke all
on function public.repair_unimis_invited_user(text)
from public;

grant execute
on function public.repair_unimis_invited_user(text)
to authenticated;

notify pgrst, 'reload schema';
