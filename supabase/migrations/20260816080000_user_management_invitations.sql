-- UniMIS User Management + Invitations
-- Depends on existing: institutions, profiles, roles, institution_users, has_permission(uuid,text)

do $$
begin
  if not exists (select 1 from pg_type where typname = 'invitation_status') then
    create type public.invitation_status as enum ('pending','accepted','expired','revoked');
  end if;
end $$;

create table if not exists public.user_invitations (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  email text not null,
  first_name text,
  middle_name text,
  last_name text,
  role_id uuid not null references public.roles(id),
  staff_number text,
  student_number text,
  status public.invitation_status not null default 'pending',
  token uuid not null default gen_random_uuid(),
  invited_by uuid references auth.users(id) on delete set null,
  expires_at timestamptz not null default (now() + interval '7 days'),
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_user_invitations_institution on public.user_invitations(institution_id);
create index if not exists idx_user_invitations_email on public.user_invitations(lower(email));
create index if not exists idx_user_invitations_role on public.user_invitations(role_id);
create unique index if not exists idx_user_invitations_token on public.user_invitations(token);
create unique index if not exists idx_user_invitations_pending_unique
on public.user_invitations(institution_id, lower(email)) where status = 'pending';

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;

drop trigger if exists trg_user_invitations_updated_at on public.user_invitations;
create trigger trg_user_invitations_updated_at
before update on public.user_invitations
for each row execute function public.set_updated_at();

alter table public.user_invitations enable row level security;

drop policy if exists "User managers can view invitations" on public.user_invitations;
create policy "User managers can view invitations"
on public.user_invitations for select to authenticated
using (public.has_permission(institution_id, 'users.view'));

drop policy if exists "User managers can create invitations" on public.user_invitations;
create policy "User managers can create invitations"
on public.user_invitations for insert to authenticated
with check (
  public.has_permission(institution_id, 'users.manage')
  and invited_by = auth.uid()
);

drop policy if exists "User managers can update invitations" on public.user_invitations;
create policy "User managers can update invitations"
on public.user_invitations for update to authenticated
using (public.has_permission(institution_id, 'users.manage'))
with check (public.has_permission(institution_id, 'users.manage'));

drop policy if exists "User managers can delete invitations" on public.user_invitations;
create policy "User managers can delete invitations"
on public.user_invitations for delete to authenticated
using (public.has_permission(institution_id, 'users.manage'));

create or replace function public.create_user_invitation(
  p_institution_id uuid,
  p_email text,
  p_role_id uuid,
  p_first_name text default null,
  p_middle_name text default null,
  p_last_name text default null,
  p_staff_number text default null,
  p_student_number text default null
)
returns public.user_invitations
language plpgsql security definer set search_path = public
as $$
declare
  v_invitation public.user_invitations;
  v_email text;
begin
  v_email := lower(trim(p_email));
  if v_email is null or v_email = '' then raise exception 'Email address is required'; end if;

  if not public.has_permission(p_institution_id, 'users.manage') then
    raise exception 'You do not have permission to manage users';
  end if;

  if not exists (
    select 1 from public.roles r
    where r.id = p_role_id and r.is_active = true
      and (r.institution_id is null or r.institution_id = p_institution_id)
  ) then raise exception 'Invalid role for this institution'; end if;

  if exists (
    select 1 from auth.users au
    join public.institution_users iu on iu.user_id = au.id
    where lower(au.email) = v_email
      and iu.institution_id = p_institution_id
      and iu.status = 'active'
  ) then raise exception 'This user is already an active member of the institution'; end if;

  update public.user_invitations
  set status = 'expired'
  where institution_id = p_institution_id
    and lower(email) = v_email and status = 'pending' and expires_at <= now();

  if exists (
    select 1 from public.user_invitations
    where institution_id = p_institution_id
      and lower(email) = v_email and status = 'pending' and expires_at > now()
  ) then raise exception 'A pending invitation already exists for this email'; end if;

  insert into public.user_invitations (
    institution_id,email,first_name,middle_name,last_name,role_id,
    staff_number,student_number,invited_by
  ) values (
    p_institution_id,v_email,nullif(trim(p_first_name),''),
    nullif(trim(p_middle_name),''),nullif(trim(p_last_name),''),
    p_role_id,nullif(trim(p_staff_number),''),nullif(trim(p_student_number),''),
    auth.uid()
  ) returning * into v_invitation;

  return v_invitation;
end;
$$;

revoke all on function public.create_user_invitation(uuid,text,uuid,text,text,text,text,text) from public;
grant execute on function public.create_user_invitation(uuid,text,uuid,text,text,text,text,text) to authenticated;

create or replace function public.revoke_user_invitation(p_invitation_id uuid)
returns void language plpgsql security definer set search_path = public
as $$
declare v_institution_id uuid;
begin
  select institution_id into v_institution_id from public.user_invitations where id=p_invitation_id;
  if v_institution_id is null then raise exception 'Invitation not found'; end if;
  if not public.has_permission(v_institution_id,'users.manage') then
    raise exception 'You do not have permission to manage users';
  end if;
  update public.user_invitations set status='revoked',updated_at=now()
  where id=p_invitation_id and status='pending';
end;
$$;
revoke all on function public.revoke_user_invitation(uuid) from public;
grant execute on function public.revoke_user_invitation(uuid) to authenticated;

create or replace function public.refresh_user_invitation(p_invitation_id uuid)
returns public.user_invitations
language plpgsql security definer set search_path = public
as $$
declare v_invitation public.user_invitations;
begin
  select * into v_invitation from public.user_invitations where id=p_invitation_id;
  if v_invitation.id is null then raise exception 'Invitation not found'; end if;
  if not public.has_permission(v_invitation.institution_id,'users.manage') then
    raise exception 'You do not have permission to manage users';
  end if;
  if v_invitation.status='accepted' then raise exception 'Accepted invitations cannot be resent'; end if;
  update public.user_invitations
  set token=gen_random_uuid(),status='pending',expires_at=now()+interval '7 days',updated_at=now()
  where id=p_invitation_id returning * into v_invitation;
  return v_invitation;
end;
$$;
revoke all on function public.refresh_user_invitation(uuid) from public;
grant execute on function public.refresh_user_invitation(uuid) to authenticated;

create or replace function public.set_institution_user_status(
  p_institution_user_id uuid, p_status text
)
returns void language plpgsql security definer set search_path=public
as $$
declare v_institution_id uuid; v_user_id uuid;
begin
  if p_status not in ('active','inactive','suspended') then raise exception 'Invalid user status'; end if;
  select institution_id,user_id into v_institution_id,v_user_id
  from public.institution_users where id=p_institution_user_id;
  if v_institution_id is null then raise exception 'Institution user not found'; end if;
  if not public.has_permission(v_institution_id,'users.manage') then
    raise exception 'You do not have permission to manage users';
  end if;
  if v_user_id=auth.uid() and p_status<>'active' then
    raise exception 'You cannot deactivate your own account';
  end if;
  update public.institution_users set status=p_status where id=p_institution_user_id;
end;
$$;
revoke all on function public.set_institution_user_status(uuid,text) from public;
grant execute on function public.set_institution_user_status(uuid,text) to authenticated;

create or replace function public.change_institution_user_role(
  p_institution_user_id uuid, p_role_id uuid
)
returns void language plpgsql security definer set search_path=public
as $$
declare v_institution_id uuid; v_user_id uuid;
begin
  select institution_id,user_id into v_institution_id,v_user_id
  from public.institution_users where id=p_institution_user_id;
  if v_institution_id is null then raise exception 'Institution user not found'; end if;
  if not public.has_permission(v_institution_id,'users.manage') then
    raise exception 'You do not have permission to manage users';
  end if;
  if not exists (
    select 1 from public.roles r where r.id=p_role_id and r.is_active=true
      and (r.institution_id is null or r.institution_id=v_institution_id)
  ) then raise exception 'Invalid role for this institution'; end if;
  if v_user_id=auth.uid() then raise exception 'You cannot change your own role'; end if;
  update public.institution_users set role_id=p_role_id where id=p_institution_user_id;
end;
$$;
revoke all on function public.change_institution_user_role(uuid,uuid) from public;
grant execute on function public.change_institution_user_role(uuid,uuid) to authenticated;

create or replace view public.institution_user_directory
with (security_invoker=true)
as
select
  iu.id as institution_user_id, iu.institution_id, iu.user_id,
  p.first_name,p.middle_name,p.last_name,p.display_name,p.phone,p.avatar_url,
  iu.staff_number,iu.student_number,iu.role_id,
  r.code as role_code,r.name as role_name,
  iu.status,iu.is_primary,iu.joined_at,iu.created_at
from public.institution_users iu
left join public.profiles p on p.id=iu.user_id
left join public.roles r on r.id=iu.role_id;

grant select on public.institution_user_directory to authenticated;
