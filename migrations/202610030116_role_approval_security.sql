begin;
insert into public.roles(name,code,is_system_role,is_active)
select 'Auditor','auditor',true,true where not exists(select 1 from public.roles where code='auditor' and institution_id is null);
delete from public.role_permissions rp using public.roles r,public.permissions p where rp.role_id=r.id and rp.permission_id=p.id and r.code='auditor' and p.code not like '%.view';
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r cross join public.permissions p
where r.code='auditor' and (p.code like '%.view' or p.code='audit.view')
on conflict do nothing;

-- The existing protected Owner is the school approval authority, not a platform login.
create or replace function public.unimis_is_access_authority116(p_inst uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.institution_users m join public.roles r on r.id=m.role_id
 where m.institution_id=p_inst and m.user_id=auth.uid() and m.status='active'
 and r.code='owner' and r.is_active)
$$;
revoke all on function public.unimis_is_access_authority116(uuid) from public;
grant execute on function public.unimis_is_access_authority116(uuid) to authenticated;

create table public.unimis_access_requests116(
 id uuid primary key default gen_random_uuid(),
 institution_id uuid not null references public.institutions(id),
 action text not null check(action in ('invite','primary_role','add_role','remove_role')),
 target_user_id uuid references auth.users(id),
 email text,
 role_id uuid not null references public.roles(id),
 previous_role_id uuid,
 first_name text,middle_name text,last_name text,
 reason text not null check(length(trim(reason))>=10),
 requested_by uuid not null references auth.users(id),
 status text not null default 'pending' check(status in ('pending','approved','rejected','executed','cancelled')),
 reviewed_by uuid references auth.users(id),review_note text,reviewed_at timestamptz,
 created_at timestamptz not null default now(),
 check(reviewed_by is null or (reviewed_by<>requested_by and reviewed_by is distinct from target_user_id))
);
create unique index unimis_access_pending116 on public.unimis_access_requests116
 (institution_id,action,coalesce(target_user_id::text,lower(email)),role_id) where status='pending';
alter table public.unimis_access_requests116 enable row level security;
revoke all on public.unimis_access_requests116 from anon,authenticated;
grant select on public.unimis_access_requests116 to authenticated;
create policy access_requests_read116 on public.unimis_access_requests116 for select to authenticated
 using(public.has_permission(institution_id,'users.manage') or public.unimis_is_access_authority116(institution_id));

create table public.unimis_additional_roles116(
 institution_user_id uuid not null references public.institution_users(id) on delete cascade,
 role_id uuid not null references public.roles(id),
 request_id uuid not null unique references public.unimis_access_requests116(id),
 granted_by uuid not null references auth.users(id),granted_at timestamptz not null default now(),
 primary key(institution_user_id,role_id)
);
alter table public.unimis_additional_roles116 enable row level security;
revoke all on public.unimis_additional_roles116 from anon,authenticated;
grant select on public.unimis_additional_roles116 to authenticated;
create policy additional_roles_read116 on public.unimis_additional_roles116 for select to authenticated
 using(exists(select 1 from public.institution_users m where m.id=institution_user_id
 and (m.user_id=auth.uid() or public.has_permission(m.institution_id,'users.manage'))));

create or replace view public.unimis_effective_memberships116 as
 select m.* from public.institution_users m join public.roles r on r.id=m.role_id and r.is_active
 union all
 select m.id,m.institution_id,m.user_id,a.role_id,m.staff_number,m.student_number,
 m.status,false,m.joined_at,m.created_at,m.updated_at
 from public.institution_users m join public.unimis_additional_roles116 a on a.institution_user_id=m.id
 join public.roles r on r.id=a.role_id and r.is_active
 where a.role_id is distinct from m.role_id;
revoke all on public.unimis_effective_memberships116 from public,anon,authenticated;

create or replace function public.has_permission(requested_institution_id uuid,requested_permission_code text)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.unimis_effective_memberships116 m
 join public.roles r on r.id=m.role_id join public.role_permissions rp on rp.role_id=r.id
 join public.permissions p on p.id=rp.permission_id
 where m.institution_id=requested_institution_id and m.user_id=auth.uid() and m.status='active'
 and r.is_active and (r.institution_id is null or r.institution_id=m.institution_id)
 and p.code=requested_permission_code)
$$;
revoke all on function public.has_permission(uuid,text) from public;
grant execute on function public.has_permission(uuid,text) to authenticated;

create or replace function public.unimis_access_role_valid116(p_inst uuid,p_role uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.roles r where r.id=p_role and r.is_active
 and (r.institution_id is null or r.institution_id=p_inst)
 and r.code not in ('owner','superadmin','super_admin','platform_superadmin','student','parent'))
$$;
revoke all on function public.unimis_access_role_valid116(uuid,uuid) from public;

create or replace function public.unimis_request_access116(p_inst uuid,p_action text,p_role uuid,
 p_reason text,p_target uuid default null,p_email text default null,
 p_first text default null,p_middle text default null,p_last text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare m public.institution_users; rid uuid; v_email text:=lower(trim(p_email)); v_code text;
begin
 if auth.uid() is null or not (public.has_permission(p_inst,'users.manage') or public.unimis_is_access_authority116(p_inst)) then raise exception 'User management access required'; end if;
 if not public.unimis_access_role_valid116(p_inst,p_role) then raise exception 'This role cannot be assigned through school user management'; end if;
 if length(trim(coalesce(p_reason,'')))<10 then raise exception 'Explain the appointment or access reason (at least 10 characters)'; end if;
 if p_action='invite' then
  if exists(select 1 from auth.users u join public.unimis_platform_operators116 op on op.user_id=u.id where lower(u.email)=v_email and op.active) then raise exception 'Platform operators must use a separate school account'; end if;
  if v_email is null or v_email!~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'A valid invitation email is required'; end if;
  if exists(select 1 from auth.users u where u.id=auth.uid() and lower(u.email)=v_email) then raise exception 'You cannot invite yourself'; end if;
  if exists(select 1 from auth.users u join public.institution_users x on x.user_id=u.id where lower(u.email)=v_email and x.institution_id=p_inst) then raise exception 'This account already belongs to the school; request a role change instead'; end if;
 elsif p_action in ('primary_role','add_role','remove_role') then
  select * into m from public.institution_users where institution_id=p_inst and user_id=p_target;
  if m.id is null then raise exception 'Target user is not a school member'; end if;
  if m.user_id=auth.uid() then raise exception 'Administrators cannot request changes to their own access; another officer must submit the request'; end if;
  if exists(select 1 from public.roles where id=m.role_id and code in ('owner','superadmin','super_admin','platform_superadmin','student','parent')) then raise exception 'Protected and student accounts cannot be changed here'; end if;
  if p_action='primary_role' and m.role_id=p_role then raise exception 'This is already the primary role'; end if;
  if p_action='add_role' and (m.role_id=p_role or exists(select 1 from public.unimis_additional_roles116 where institution_user_id=m.id and role_id=p_role)) then raise exception 'This role is already assigned'; end if;
  if p_action='remove_role' and not exists(select 1 from public.unimis_additional_roles116 where institution_user_id=m.id and role_id=p_role) then raise exception 'Additional role not found'; end if;
 else raise exception 'Unknown access action'; end if;
 insert into public.unimis_access_requests116(institution_id,action,target_user_id,email,role_id,previous_role_id,first_name,middle_name,last_name,reason,requested_by)
 values(p_inst,p_action,case when p_action='invite' then null else p_target end,case when p_action='invite' then v_email end,p_role,m.role_id,p_first,p_middle,p_last,trim(p_reason),auth.uid()) returning id into rid;
 return rid;
end $$;
revoke all on function public.unimis_request_access116(uuid,text,uuid,text,uuid,text,text,text,text) from public;
grant execute on function public.unimis_request_access116(uuid,text,uuid,text,uuid,text,text,text,text) to authenticated;

create or replace function public.unimis_review_access116(p_request uuid,p_approve boolean,p_note text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare req public.unimis_access_requests116; m public.institution_users; v_code text;
begin
 select * into req from public.unimis_access_requests116 where id=p_request for update;
 if req.id is null then raise exception 'Access request not found'; end if;
 if not public.unimis_is_access_authority116(req.institution_id) then raise exception 'Only the school approval authority can decide access requests'; end if;
 if auth.uid()=req.requested_by or auth.uid()=req.target_user_id or exists(select 1 from auth.users u where u.id=auth.uid() and lower(u.email)=req.email) then raise exception 'You cannot approve your own request or access'; end if;
 if req.status<>'pending' then raise exception 'This request has already been decided'; end if;
 if length(trim(coalesce(p_note,'')))<5 then raise exception 'A decision note is required'; end if;
 if not public.unimis_access_role_valid116(req.institution_id,req.role_id) then raise exception 'The requested role is no longer available'; end if;
 if p_approve then
  select code into v_code from public.roles where id=req.role_id;
  if req.action<>'invite' then
   select * into m from public.institution_users where institution_id=req.institution_id and user_id=req.target_user_id for update;
   if m.id is null or m.role_id is distinct from req.previous_role_id then raise exception 'The membership changed; submit a fresh request'; end if;
   if exists(select 1 from public.roles where id=m.role_id and code in ('owner','student','parent','superadmin','super_admin','platform_superadmin')) then raise exception 'Protected account'; end if;
   if req.action<>'remove_role' and (v_code='auditor' and exists(select 1 from public.unimis_additional_roles116 where institution_user_id=m.id) or v_code<>'auditor' and exists(select 1 from public.unimis_additional_roles116 a join public.roles r on r.id=a.role_id where a.institution_user_id=m.id and r.code='auditor') or req.action='add_role' and (v_code='auditor' or exists(select 1 from public.roles where id=m.role_id and code='auditor'))) then raise exception 'Auditor access cannot be combined with operational roles'; end if;
  end if;
 end if;
 update public.unimis_access_requests116 set status=case when p_approve then 'approved' else 'rejected' end,reviewed_by=auth.uid(),reviewed_at=now(),review_note=trim(p_note) where id=req.id;
 if p_approve and req.action='primary_role' then
  update public.institution_users set role_id=req.role_id,updated_at=now() where id=m.id;
 elsif p_approve and req.action='add_role' then
  insert into public.unimis_additional_roles116(institution_user_id,role_id,request_id,granted_by) values(m.id,req.role_id,req.id,auth.uid());
 elsif p_approve and req.action='remove_role' then
  delete from public.unimis_additional_roles116 where institution_user_id=m.id and role_id=req.role_id;
 end if;
 if p_approve and req.action<>'invite' then update public.unimis_access_requests116 set status='executed' where id=req.id; end if;
 return jsonb_build_object('ok',true,'status',case when not p_approve then 'rejected' when req.action='invite' then 'approved' else 'executed' end);
end $$;
revoke all on function public.unimis_review_access116(uuid,boolean,text) from public;
grant execute on function public.unimis_review_access116(uuid,boolean,text) to authenticated;

alter table public.user_invitations add column approval_request_id uuid references public.unimis_access_requests116(id);
create or replace function public.unimis_guard_invitation116()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_code text;
begin
 if tg_op='UPDATE' and (new.institution_id is distinct from old.institution_id or new.email is distinct from old.email or new.role_id is distinct from old.role_id or new.invited_by is distinct from old.invited_by or new.approval_request_id is distinct from old.approval_request_id) then raise exception 'Invitation identity and approved role are immutable; create a fresh request'; end if;
 select code into v_code from public.roles where id=new.role_id and is_active and (institution_id is null or institution_id=new.institution_id);
 if v_code is null or v_code in ('owner','superadmin','super_admin','platform_superadmin','student','parent') then raise exception 'Invalid invitation role'; end if;
 if tg_op='INSERT' or new.status='pending' then
  if not exists(select 1 from public.unimis_access_requests116 q
   where q.id=new.approval_request_id and q.institution_id=new.institution_id and q.action='invite'
   and q.role_id=new.role_id and lower(q.email)=lower(new.email) and q.status='approved'
   and q.reviewed_by<>q.requested_by and q.reviewed_by is not null) then raise exception 'An independently approved invitation request is required'; end if;
 end if;
 return new;
end $$;
update public.user_invitations set status='revoked',updated_at=now() where status='pending' and approval_request_id is null;
create trigger unimis_invitation_guard116 before insert or update on public.user_invitations for each row execute function public.unimis_guard_invitation116();

-- All staff invitations go through approval; no privileged role allowlist can be bypassed with custom roles.
create or replace function public.create_user_invitation(p_institution_id uuid,p_email text,p_role_id uuid,p_first_name text default null,p_middle_name text default null,p_last_name text default null,p_staff_number text default null,p_student_number text default null)
returns public.user_invitations language plpgsql security definer set search_path='' as $$
declare q public.unimis_access_requests116; inv public.user_invitations; v_email text:=lower(trim(p_email));
begin
 if not (public.has_permission(p_institution_id,'users.manage') or public.unimis_is_access_authority116(p_institution_id)) then raise exception 'User management access required'; end if;
 if exists(select 1 from auth.users where id=auth.uid() and lower(email)=v_email) then raise exception 'You cannot invite yourself'; end if;
 select * into q from public.unimis_access_requests116 where institution_id=p_institution_id and action='invite' and email=v_email and role_id=p_role_id and status='approved' order by reviewed_at desc limit 1 for update;
 if q.id is null then raise exception 'Submit an invitation request and obtain independent approval first'; end if;
 if exists(select 1 from auth.users u join public.institution_users m on m.user_id=u.id where lower(u.email)=v_email and m.institution_id=p_institution_id) then raise exception 'Existing school member; use a role request'; end if;
 select * into inv from public.user_invitations where approval_request_id=q.id and status='pending' and expires_at>now() order by created_at desc limit 1;
 if inv.id is not null then return inv; end if;
 update public.user_invitations set status='expired' where institution_id=p_institution_id and lower(email)=v_email and status='pending';
 insert into public.user_invitations(institution_id,email,role_id,first_name,middle_name,last_name,staff_number,student_number,invited_by,approval_request_id)
 values(p_institution_id,v_email,p_role_id,q.first_name,q.middle_name,q.last_name,p_staff_number,p_student_number,q.requested_by,q.id) returning * into inv;
 return inv;
end $$;

create or replace function public.unimis_prepare_invitation116(p_inst uuid,p_invitation uuid)
returns public.user_invitations language plpgsql security definer set search_path='' as $$
declare inv public.user_invitations;
begin
 if not (public.has_permission(p_inst,'users.manage') or public.unimis_is_access_authority116(p_inst)) then raise exception 'User management access required'; end if;
 select * into inv from public.user_invitations where id=p_invitation and institution_id=p_inst for update;
 if inv.id is null or inv.status<>'pending' then raise exception 'Pending invitation not found'; end if;
 if exists(select 1 from auth.users where id=auth.uid() and lower(email)=lower(inv.email)) then raise exception 'You cannot invite yourself'; end if;
 update public.user_invitations set expires_at=now()+interval '7 days',updated_at=now() where id=inv.id returning * into inv;
 return inv;
end $$;
revoke all on function public.unimis_prepare_invitation116(uuid,uuid) from public;
grant execute on function public.unimis_prepare_invitation116(uuid,uuid) to authenticated;

-- Memberships are immutable except through a reviewed request or a validated invitation.
create or replace function public.unimis_guard_membership116()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_code text; v_old_code text; v_email text;
begin
 if tg_op='DELETE' then
  if exists(select 1 from public.roles where id=old.role_id and code in ('owner','superadmin','super_admin','platform_superadmin')) then raise exception 'Protected authority account cannot be deleted'; end if;
  if auth.uid()=old.user_id then raise exception 'You cannot delete your own membership'; end if;
  return old;
 end if;
 if tg_op='UPDATE' then
  if new.user_id is distinct from old.user_id or new.institution_id is distinct from old.institution_id then raise exception 'Membership identity cannot be changed'; end if;
  select code into v_old_code from public.roles where id=old.role_id;
  if v_old_code in ('owner','superadmin','super_admin','platform_superadmin') and (new.role_id is distinct from old.role_id or new.status is distinct from old.status) then raise exception 'Protected authority account'; end if;
  if auth.uid()=old.user_id and (new.role_id is distinct from old.role_id or new.status is distinct from old.status and not (old.status='pending' and new.status='active' and exists(select 1 from auth.users u join public.user_invitations i on lower(i.email)=lower(u.email) join public.unimis_access_requests116 q on q.id=i.approval_request_id where u.id=new.user_id and u.email_confirmed_at is not null and i.institution_id=new.institution_id and i.role_id=new.role_id and i.status='pending' and i.expires_at>now() and q.status='approved'))) then raise exception 'You cannot change your own role or status'; end if;
  if new.role_id is not distinct from old.role_id then
   if old.status='pending' and new.status='active' then
    if not exists(select 1 from auth.users u join public.user_invitations i on lower(i.email)=lower(u.email) join public.unimis_access_requests116 q on q.id=i.approval_request_id where u.id=new.user_id and u.email_confirmed_at is not null and i.institution_id=new.institution_id and i.role_id=new.role_id and i.status='pending' and i.expires_at>now() and q.status='approved') then raise exception 'Invitation must be confirmed and still approved before activation'; end if;
   end if;
   if new.status='active' and old.status not in ('active','pending') and v_old_code not in ('student','parent','staff') and auth.uid() is not null and not public.unimis_is_access_authority116(new.institution_id) then raise exception 'Only the school authority can reactivate privileged accounts'; end if;
   return new;
  end if;
 end if;
 if exists(select 1 from public.unimis_platform_operators116 where user_id=new.user_id and active) then raise exception 'Platform operator accounts cannot receive school memberships'; end if;
 select code into v_code from public.roles where id=new.role_id and is_active and (institution_id is null or institution_id=new.institution_id);
 if v_code is null then raise exception 'Valid school role required'; end if;
 -- Student/parent enrolment and ordinary staff provisioning remain available to existing workflows.
 if tg_op='INSERT' and v_code in ('student','parent','staff') then return new; end if;
 if auth.uid() is null and session_user in ('postgres','supabase_admin') then return new; end if;
 if tg_op='UPDATE' and exists(select 1 from public.unimis_access_requests116 q where q.institution_id=new.institution_id and q.action='primary_role' and q.target_user_id=new.user_id and q.role_id=new.role_id and q.previous_role_id=old.role_id and q.status='approved' and q.reviewed_by=auth.uid() and q.reviewed_by<>q.requested_by and q.reviewed_by<>new.user_id) then return new; end if;
 select lower(email) into v_email from auth.users where id=new.user_id;
 if tg_op='INSERT' and exists(select 1 from public.user_invitations i join public.unimis_access_requests116 q on q.id=i.approval_request_id where i.institution_id=new.institution_id and lower(i.email)=v_email and i.role_id=new.role_id and i.status='pending' and i.expires_at>now() and q.status='approved' and q.reviewed_by<>q.requested_by) then return new; end if;
 raise exception 'Role assignment requires an independently approved request';
end $$;
create trigger unimis_membership_guard116 before insert or update or delete on public.institution_users for each row execute function public.unimis_guard_membership116();

-- Metadata provided at public signup can never appoint a school officer.
create or replace function public.handle_unimis_invited_auth_user()
returns trigger language plpgsql security definer set search_path='' as $$
declare inv public.user_invitations;
begin
 if new.invited_at is null then return new; end if;
 select * into inv from public.user_invitations where id=nullif(new.raw_user_meta_data->>'invitation_id','')::uuid
 and lower(email)=lower(new.email) and status='pending' and expires_at>now();
 if inv.id is null then return new; end if;
 if not exists(select 1 from public.unimis_access_requests116 q where q.id=inv.approval_request_id and q.status='approved' and q.action='invite' and q.role_id=inv.role_id and q.institution_id=inv.institution_id and q.email=lower(new.email) and q.reviewed_by<>q.requested_by) then return new; end if;
 insert into public.profiles(id,email,first_name,middle_name,last_name,display_name,status)
 values(new.id,lower(new.email),inv.first_name,inv.middle_name,inv.last_name,coalesce(nullif(concat_ws(' ',inv.first_name,inv.last_name),''),new.email),'active')
 on conflict(id) do update set email=excluded.email;
 insert into public.institution_users(institution_id,user_id,role_id,staff_number,student_number,status,is_primary)
 values(inv.institution_id,new.id,inv.role_id,inv.staff_number,inv.student_number,'pending',true)
 on conflict(institution_id,user_id) do nothing;
 return new;
end $$;

create or replace function public.accept_own_user_invitation()
returns boolean language plpgsql security definer set search_path='' as $$
declare u auth.users; inv public.user_invitations;
begin
 select * into u from auth.users where id=auth.uid();
 if u.id is null or u.email_confirmed_at is null then return false; end if;
 for inv in select * from public.user_invitations where lower(email)=lower(u.email) and status='pending' and expires_at>now() for update loop
  if exists(select 1 from public.unimis_access_requests116 q where q.id=inv.approval_request_id and q.status='approved' and q.role_id=inv.role_id and q.institution_id=inv.institution_id and q.email=lower(u.email) and q.reviewed_by<>q.requested_by) then
   insert into public.institution_users(institution_id,user_id,role_id,status,is_primary) values(inv.institution_id,u.id,inv.role_id,'active',true) on conflict(institution_id,user_id) do nothing;
   if exists(select 1 from public.institution_users where institution_id=inv.institution_id and user_id=u.id and role_id=inv.role_id) then
    update public.institution_users set status='active',updated_at=now() where institution_id=inv.institution_id and user_id=u.id and role_id=inv.role_id and status='pending';
    update public.user_invitations set status='accepted',accepted_at=now() where id=inv.id;
    update public.unimis_access_requests116 set status='executed' where id=inv.approval_request_id;
   end if;
  end if;
 end loop;
 return true;
end $$;

-- Stop alternate API endpoints from bypassing the review workflow.
revoke insert,update,delete on public.institution_users,public.user_invitations from authenticated;
grant select on public.institution_users,public.user_invitations to authenticated;
create or replace function public.change_institution_user_role(p_institution_user_id uuid,p_role_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin raise exception 'Use Access Requests: another officer must approve role changes'; end $$;

create or replace function public.unimis_guard_role_definition116()
returns trigger language plpgsql security definer set search_path='' as $$
declare inst uuid; v_code text; v_perm text;
begin
 if tg_table_name='roles' then
  if tg_op='INSERT' then v_code:=new.code; else v_code:=old.code; end if;
  if auth.uid() is not null and v_code in ('owner','superadmin','super_admin','platform_superadmin') then raise exception 'Protected authority roles cannot be edited in school user management'; end if;
  if tg_op='DELETE' then inst:=old.institution_id; else inst:=new.institution_id; end if;
  if tg_op='UPDATE' and (new.institution_id is distinct from old.institution_id or new.code is distinct from old.code) then raise exception 'Role identity cannot be changed'; end if;
 else
  if tg_op='DELETE' then select institution_id into inst from public.roles where id=old.role_id; else select institution_id into inst from public.roles where id=new.role_id; end if;
 end if;
 if tg_table_name='role_permissions' and tg_op<>'DELETE' then
  select code into v_code from public.roles where id=new.role_id;
  select code into v_perm from public.permissions where id=new.permission_id;
  if v_code='auditor' and v_perm not like '%.view' then raise exception 'Auditor permissions must be read-only'; end if;
 end if;
 if auth.uid() is not null and (inst is null or not public.unimis_is_access_authority116(inst)) then raise exception 'Only the school authority can maintain institutional role definitions'; end if;
 if tg_op='DELETE' then return old; else return new; end if;
end $$;
create trigger unimis_role_definition_guard116 before insert or update or delete on public.roles for each row execute function public.unimis_guard_role_definition116();
create trigger unimis_role_permission_guard116 before insert or update or delete on public.role_permissions for each row execute function public.unimis_guard_role_definition116();

create or replace function public.unimis_access_workspace116(p_inst uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not (public.has_permission(p_inst,'users.manage') or public.unimis_is_access_authority116(p_inst)) then raise exception 'User management access required'; end if;
 return jsonb_build_object('can_approve',public.unimis_is_access_authority116(p_inst),'actor',auth.uid(),
 'requests',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select q.*,r.name role_name,(select email from auth.users where id=q.requested_by) requester_email,(select email from auth.users where id=q.reviewed_by) reviewer_email,(select email from auth.users where id=q.target_user_id) target_email from public.unimis_access_requests116 q join public.roles r on r.id=q.role_id where q.institution_id=p_inst) x),'[]'::jsonb),
 'additional_roles',coalesce((select jsonb_agg(jsonb_build_object('user_id',m.user_id,'role_id',a.role_id,'role_name',r.name,'granted_at',a.granted_at,'granted_by',a.granted_by)) from public.unimis_additional_roles116 a join public.institution_users m on m.id=a.institution_user_id join public.roles r on r.id=a.role_id where m.institution_id=p_inst),'[]'::jsonb));
end $$;
revoke all on function public.unimis_access_workspace116(uuid) from public;
grant execute on function public.unimis_access_workspace116(uuid) to authenticated;

create or replace function public.unimis_my_additional_roles116()
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('institution_id',m.institution_id,'role_id',a.role_id,'role',jsonb_build_object('id',r.id,'name',r.name,'code',r.code,'is_active',r.is_active))),'[]'::jsonb)
 from public.unimis_additional_roles116 a join public.institution_users m on m.id=a.institution_user_id join public.roles r on r.id=a.role_id
 where m.user_id=auth.uid() and m.status='active' and r.is_active
$$;
revoke all on function public.unimis_my_additional_roles116() from public;
grant execute on function public.unimis_my_additional_roles116() to authenticated;

create or replace function public.unimis_current_lecturer()
returns table(institution_id uuid, staff_id uuid, lecturer_profile_id uuid)
language sql security definer set search_path=''
as $$
  select iu.institution_id, s.id, lp.id
  from public.unimis_effective_memberships116 iu
  join public.roles r on r.id=iu.role_id and r.code='lecturer'
  join public.staff s on s.institution_id=iu.institution_id
    and (s.staff_number=iu.staff_number
         or lower(s.email)=lower(coalesce((select email from auth.users where id=auth.uid()),'')))
  join public.lecturer_profiles lp on lp.staff_id=s.id
    and lp.institution_id=iu.institution_id and lp.is_active=true
  where iu.user_id=auth.uid() and iu.status='active'
  order by iu.is_primary desc nulls last, iu.joined_at
  limit 1
$$;
create or replace function public.unimis_reporting_access()
returns uuid language sql stable security definer set search_path='' as $$
 select iu.institution_id from public.unimis_effective_memberships116 iu
 join public.roles r on r.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active'
 and lower(coalesce(r.code,r.name)) in ('owner','registrar','superadmin','super_admin','exam_officer','exams_officer','examination_officer','examinations_officer')
 limit 1
$$;
create or replace function public.unimis_progression_access()
returns uuid language sql stable security definer set search_path='' as $$
 select iu.institution_id from public.unimis_effective_memberships116 iu
 join public.roles r on r.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active'
 and lower(coalesce(r.code,r.name)) in ('owner','registrar','superadmin','super_admin','exam_officer','exams_officer','examination_officer','examinations_officer')
 limit 1
$$;
create or replace function public.unimis_finance_institution()
returns uuid language sql stable security definer set search_path='' as $$
 select iu.institution_id from public.unimis_effective_memberships116 iu
 join public.roles r on r.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active'
 and lower(coalesce(r.code,r.name)) in ('owner','finance_officer','auditor','accountant','superadmin','super_admin')
 order by iu.is_primary desc limit 1
$$;
create or replace function public.unimis_results_admin_queue()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid;
begin
 select iu.institution_id into v_inst
 from public.unimis_effective_memberships116 iu join public.roles r on r.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active' and r.code in ('owner','registrar','exam_officer') limit 1;
 if v_inst is null then raise exception 'Administrator access required'; end if;
 return coalesce((
  select jsonb_agg(x order by x->>'course_code')
  from (
   select jsonb_build_object(
    'course_offering_id',cr.course_offering_id,'course_code',c.code,'course_name',c.name,
    'academic_period_id',co.academic_period_id,'result_status',min(cr.result_status),
    'student_count',count(*),'submitted_at',max(cr.submitted_at),'approved_at',max(cr.approved_at),'published_at',max(cr.published_at)
   ) x
   from public.course_results cr join public.course_offerings co on co.id=cr.course_offering_id join public.courses c on c.id=co.course_id
   where cr.institution_id=v_inst
   group by cr.course_offering_id,c.code,c.name,co.academic_period_id
  ) q
 ),'[]'::jsonb);
end $$;
create or replace function public.unimis_admin_course_results(p_course_offering_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid;
begin
 select iu.institution_id into v_inst from public.unimis_effective_memberships116 iu join public.roles r on r.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active' and r.code in ('owner','registrar','exam_officer') limit 1;
 if v_inst is null then raise exception 'Administrator access required'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',cr.id,'student_number',s.student_number,'student_name',concat_ws(' ',s.first_name,s.middle_name,s.last_name),'total_score',cr.total_score,'letter_grade',cr.letter_grade,'grade_point',cr.grade_point,'passed',cr.passed,'result_status',cr.result_status,'remarks',cr.remarks) order by s.last_name,s.first_name)
 from public.course_results cr join public.students s on s.id=cr.student_id where cr.institution_id=v_inst and cr.course_offering_id=p_course_offering_id),'[]'::jsonb);
end $$;
create or replace function public.unimis_admin_result_action(p_course_offering_id uuid,p_action text,p_notes text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid; v_old text; v_new text; n int:=0; r record;
begin
 select iu.institution_id into v_inst from public.unimis_effective_memberships116 iu join public.roles ro on ro.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active' and ro.code in ('owner','registrar','exam_officer') limit 1;
 if v_inst is null then raise exception 'Administrator access required'; end if;
 if p_action='approve' then v_old:='submitted';v_new:='approved';
 elsif p_action='publish' then v_old:='approved';v_new:='published';
 elsif p_action='return' then v_old:='submitted';v_new:='draft';
 else raise exception 'Invalid result action'; end if;
 for r in select id from public.course_results where institution_id=v_inst and course_offering_id=p_course_offering_id and result_status=v_old loop
   update public.course_results set result_status=v_new,
     approved_by=case when v_new='approved' then auth.uid() when v_new='draft' then null else approved_by end,
     approved_at=case when v_new='approved' then now() when v_new='draft' then null else approved_at end,
     published_at=case when v_new='published' then now() when v_new='draft' then null else published_at end,
     remarks=case when nullif(btrim(coalesce(p_notes,'')),'') is not null then p_notes else remarks end,updated_at=now()
   where id=r.id;
   insert into public.result_approval_history(institution_id,course_result_id,old_status,new_status,action_by,action_at,notes)
   values(v_inst,r.id,v_old,v_new,auth.uid(),now(),nullif(btrim(coalesce(p_notes,'')),''));
   n:=n+1;
 end loop;
 if n=0 then raise exception 'No % results found for this course',v_old; end if;
 return jsonb_build_object('updated',n,'status',v_new);
end $$;
create or replace function public.unimis_finance_dashboard()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid;
begin
 select iu.institution_id into v_inst from public.unimis_effective_memberships116 iu join public.roles r on r.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active' and r.code in ('owner','finance_officer')
 order by iu.is_primary desc limit 1;
 if v_inst is null then raise exception 'Finance access required'; end if;
 return jsonb_build_object(
  'summary',jsonb_build_object(
    'billed',coalesce((select sum(total_amount) from public.student_invoices where institution_id=v_inst and status<>'cancelled'),0),
    'collected',coalesce((select sum(amount) from public.student_payments where institution_id=v_inst and status='completed'),0),
    'outstanding',coalesce((select sum(balance) from public.student_invoices where institution_id=v_inst and status not in('cancelled','waived')),0),
    'expenses',coalesce((select sum(amount) from public.finance_expenses where institution_id=v_inst and status='posted'),0),
    'overdue_invoices',coalesce((select count(*) from public.student_invoices where institution_id=v_inst and balance>0 and due_date<current_date and status not in('cancelled','waived')),0)
  ),
  'invoices',coalesce((select jsonb_agg(to_jsonb(x) order by x.invoice_date desc) from (
    select si.id,si.invoice_number,si.invoice_date,si.due_date,si.total_amount,si.amount_paid,si.balance,si.status,si.currency_code,
           s.student_number,s.first_name,s.last_name
    from public.student_invoices si join public.students s on s.id=si.student_id where si.institution_id=v_inst limit 100
  )x),'[]'::jsonb),
  'payments',coalesce((select jsonb_agg(to_jsonb(x) order by x.payment_date desc) from (
    select sp.id,sp.payment_reference,sp.payment_date,sp.amount,sp.currency_code,sp.payment_method,sp.status,s.student_number,s.first_name,s.last_name
    from public.student_payments sp join public.students s on s.id=sp.student_id where sp.institution_id=v_inst limit 100
  )x),'[]'::jsonb),
  'expenses',coalesce((select jsonb_agg(to_jsonb(x) order by x.expense_date desc) from (
    select e.id,e.expense_date,e.reference,e.description,e.amount,e.currency_code,e.payment_method,e.payee,e.status,c.name category
    from public.finance_expenses e left join public.finance_expense_categories c on c.id=e.category_id where e.institution_id=v_inst limit 100
  )x),'[]'::jsonb),
  'fee_types',coalesce((select jsonb_agg(to_jsonb(x) order by x.name) from (select id,code,name,is_mandatory,status from public.fee_types where institution_id=v_inst)x),'[]'::jsonb),
  'fee_structures',coalesce((select jsonb_agg(to_jsonb(x) order by x.name) from (
    select fs.id,fs.name,fs.currency_code,fs.level_number,fs.status,ay.name academic_year,ap.name academic_period,p.code programme_code,
      coalesce((select sum(fsi.amount) from public.fee_structure_items fsi where fsi.fee_structure_id=fs.id),0) total
    from public.fee_structures fs join public.academic_years ay on ay.id=fs.academic_year_id
    left join public.academic_periods ap on ap.id=fs.academic_period_id left join public.programmes p on p.id=fs.programme_id
    where fs.institution_id=v_inst
  )x),'[]'::jsonb)
 );
end $$;

-- School administrators retain user/website/core-resource permissions, not operational powers.
delete from public.role_permissions rp using public.roles r,public.permissions perm
where rp.role_id=r.id and rp.permission_id=perm.id and r.code='admin'
and perm.code not in ('users.view','users.manage','institution.view','institution.manage','institutions.view','institutions.manage','settings.view','settings.manage','website.view','website.manage');

create or replace function public.unimis_guard_results_separation116()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='UPDATE' and old.result_status in ('submitted','approved','published') and new.submitted_by is distinct from old.submitted_by then raise exception 'Submitted result preparer identity is immutable'; end if;
 if auth.uid() is not null and new.result_status in ('approved','published')
 and (tg_op='INSERT' or new.result_status is distinct from old.result_status) then
  if tg_op='INSERT' then raise exception 'A result must be submitted and independently approved before publication'; end if;
  if new.submitted_by is null or new.result_status='approved' and old.result_status<>'submitted' or new.result_status='published' and old.result_status<>'approved' then raise exception 'A recorded submission and approval sequence is required'; end if;
  if new.submitted_by=auth.uid() or exists(select 1 from public.assessment_scores x where x.student_course_registration_id=new.student_course_registration_id and x.entered_by=auth.uid()) then raise exception 'The result preparer cannot approve or publish their own results'; end if;
  if tg_op='UPDATE' and new.submitted_by is distinct from old.submitted_by then raise exception 'Submission identity cannot be changed during approval'; end if;
 end if;
 return new;
end $$;
create trigger unimis_result_separation116 before insert or update on public.course_results for each row execute function public.unimis_guard_results_separation116();

alter table public.payroll_runs add column if not exists created_by uuid references auth.users(id);
create or replace function public.unimis_guard_payroll_separation116()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='INSERT' and auth.uid() is not null then new.created_by:=auth.uid(); end if;
 if tg_op='UPDATE' and new.created_by is distinct from old.created_by then raise exception 'Payroll creator identity is immutable'; end if;
 if tg_op='UPDATE' and old.processed_by is not null and new.processed_by is distinct from old.processed_by then raise exception 'Payroll preparer identity is immutable'; end if;
 if auth.uid() is not null and new.status='approved' and (tg_op='INSERT' or old.status is distinct from new.status) then
  if new.created_by=auth.uid() or new.processed_by=auth.uid() or (tg_op='UPDATE' and old.processed_by=auth.uid()) then raise exception 'The payroll preparer cannot approve their own payroll'; end if;
  new.approved_by:=auth.uid();new.approved_at:=now();
 end if;
 return new;
end $$;
create trigger unimis_payroll_separation116 before insert or update on public.payroll_runs for each row execute function public.unimis_guard_payroll_separation116();

-- Platform operators are provisioned only by the database operator, never school user management.
create table public.unimis_platform_operators116(user_id uuid primary key references auth.users(id),active boolean not null default true,created_at timestamptz not null default now());
alter table public.unimis_platform_operators116 enable row level security;
revoke all on public.unimis_platform_operators116 from public,anon,authenticated;
create or replace function public.unimis_is_platform_operator116()
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.unimis_platform_operators116 where user_id=auth.uid() and active)
$$;
revoke all on function public.unimis_is_platform_operator116() from public;
grant execute on function public.unimis_is_platform_operator116() to authenticated;
create or replace function public.unimis_platform_workspace116()
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not public.unimis_is_platform_operator116() then raise exception 'Platform operator access required'; end if;
 return jsonb_build_object('schools',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name)) from public.institutions),'[]'::jsonb),'access_requests_pending',(select count(*) from public.unimis_access_requests116 where status='pending'),'generated_at',now());
end $$;
revoke all on function public.unimis_platform_workspace116() from public;
grant execute on function public.unimis_platform_workspace116() to authenticated;


create or replace function public.revoke_user_invitation(p_invitation_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare inv public.user_invitations;
begin
 select * into inv from public.user_invitations where id=p_invitation_id for update;
 if inv.id is null then raise exception 'Invitation not found'; end if;
 if not public.has_permission(inv.institution_id,'users.manage') then raise exception 'User management access required'; end if;
 if inv.status<>'pending' then raise exception 'Only pending invitations can be revoked'; end if;
 delete from public.institution_users m using auth.users u where m.user_id=u.id and lower(u.email)=lower(inv.email) and m.institution_id=inv.institution_id and m.role_id=inv.role_id and m.status='pending';
 update public.user_invitations set status='revoked',updated_at=now() where id=inv.id;
 update public.unimis_access_requests116 set status='cancelled' where id=inv.approval_request_id and status='approved';
end $$;

create or replace function public.repair_unimis_invited_user(p_email text)
returns void language plpgsql security definer set search_path='' as $$
begin raise exception 'Legacy metadata repair is disabled; use a verified, independently approved invitation'; end $$;
revoke all on function public.repair_unimis_invited_user(text) from public,anon,authenticated;

create or replace function public.unimis_auditor_readonly116()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is not null and exists(select 1 from public.unimis_effective_memberships116 m join public.roles r on r.id=m.role_id where m.user_id=auth.uid() and m.status='active' and r.code='auditor') then raise exception 'Auditor accounts have read-only operational access'; end if;
 if tg_op='DELETE' then return old; else return new; end if;
end $$;
do $$ declare t record; begin
 for t in select tablename from pg_catalog.pg_tables where schemaname='public'
 and tablename ~ '^(finance_|student_invoice|student_payment|fee_|procurement_|purchase_|payroll_|payslip|student_attendance|course_results|assessment_)' loop
  execute format('create trigger unimis_auditor_readonly116 before insert or update or delete on public.%I for each row execute function public.unimis_auditor_readonly116()',t.tablename);
 end loop;
end $$;

create or replace function public.unimis_audit_access_log116()
returns jsonb language plpgsql security definer set search_path='' as $$
declare inst uuid;
begin
 select m.institution_id into inst from public.unimis_effective_memberships116 m join public.roles r on r.id=m.role_id where m.user_id=auth.uid() and m.status='active' and r.code in ('auditor','owner') order by m.is_primary desc limit 1;
 if inst is null then raise exception 'Auditor access required'; end if;
 return jsonb_build_object('requests',coalesce((select jsonb_agg(jsonb_build_object('id',q.id,'action',q.action,'role',r.name,'status',q.status,'reason',q.reason,'requested_by',q.requested_by,'reviewed_by',q.reviewed_by,'created_at',q.created_at,'reviewed_at',q.reviewed_at,'review_note',q.review_note) order by q.created_at desc) from public.unimis_access_requests116 q join public.roles r on r.id=q.role_id where q.institution_id=inst),'[]'::jsonb));
end $$;
revoke all on function public.unimis_audit_access_log116() from public;
grant execute on function public.unimis_audit_access_log116() to authenticated;

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
    from public.unimis_effective_memberships116 iu
    join public.roles r on r.id=iu.role_id
    where iu.user_id=auth.uid()
      and iu.institution_id=v_inst
      and iu.status='active'
      and lower(coalesce(r.code,r.name,'')) in
          ('owner','registrar','superadmin','super_admin')
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
create or replace function public.unimis_admin_result_analytics(p_course_offering_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid;
begin
 select iu.institution_id into v_inst from public.unimis_effective_memberships116 iu join public.roles r on r.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active' and lower(coalesce(r.code,r.name)) in ('owner','registrar','superadmin','super_admin','exams_officer','examinations_officer') limit 1;
 if v_inst is null then raise exception 'Examinations review access required';end if;
 return public.unimis_result_analytics_core(v_inst,p_course_offering_id);
end $$;
create or replace function public.unimis_academic_intelligence()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid;
begin
 select iu.institution_id into v_inst
 from public.unimis_effective_memberships116 iu join public.roles r on r.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active'
 and lower(coalesce(r.code,r.name)) in ('owner','registrar','superadmin','super_admin','exams_officer','examinations_officer') limit 1;
 if v_inst is null then raise exception 'Academic review access required'; end if;
 return jsonb_build_object(
 'summary',(select jsonb_build_object('students',count(distinct cr.student_id),'courses',count(distinct cr.course_offering_id),'results',count(*),'average',round(avg(cr.total_score),2),'pass_rate',round(count(*) filter(where cr.passed)*100.0/nullif(count(*),0),1),'failures',count(*) filter(where not coalesce(cr.passed,false))) from public.course_results cr where cr.institution_id=v_inst and cr.result_status in ('submitted','approved','published')),
 'courses',coalesce((select jsonb_agg(to_jsonb(x) order by x.fail_rate desc) from (
 select co.id course_offering_id,c.code course_code,c.name course_name,p.code programme_code,co.level_number,ap.name academic_period,count(*) students,round(avg(cr.total_score),2) average,round(count(*) filter(where cr.passed)*100.0/nullif(count(*),0),1) pass_rate,round(count(*) filter(where not coalesce(cr.passed,false))*100.0/nullif(count(*),0),1) fail_rate,min(cr.total_score) lowest,max(cr.total_score) highest
 from public.course_results cr join public.course_offerings co on co.id=cr.course_offering_id join public.courses c on c.id=co.course_id left join public.programmes p on p.id=co.programme_id join public.academic_periods ap on ap.id=co.academic_period_id
 where cr.institution_id=v_inst and cr.result_status in ('submitted','approved','published')
 group by co.id,c.code,c.name,p.code,co.level_number,ap.name) x),'[]'::jsonb),
 'students',coalesce((select jsonb_agg(to_jsonb(z) order by z.average) from (
 select s.id student_id,s.student_number,concat_ws(' ',s.first_name,s.middle_name,s.last_name) student_name,count(*) courses,round(avg(cr.total_score),2) average,min(cr.total_score) weakest_score,max(cr.total_score) strongest_score,round(stddev_pop(cr.total_score),2) variation,count(*) filter(where not coalesce(cr.passed,false)) failed_courses
 from public.course_results cr join public.students s on s.id=cr.student_id
 where cr.institution_id=v_inst and cr.result_status in ('submitted','approved','published')
 group by s.id,s.student_number,s.first_name,s.middle_name,s.last_name) z),'[]'::jsonb));
end $$;
create or replace function public.unimis_student_academic_profile(p_student_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid;
begin
 select iu.institution_id into v_inst from public.unimis_effective_memberships116 iu join public.roles r on r.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active' and lower(coalesce(r.code,r.name)) in ('owner','registrar','superadmin','super_admin','exams_officer','examinations_officer') limit 1;
 if v_inst is null then raise exception 'Academic review access required'; end if;
 return jsonb_build_object(
 'student',(select jsonb_build_object('student_number',s.student_number,'student_name',concat_ws(' ',s.first_name,s.middle_name,s.last_name)) from public.students s where s.id=p_student_id and s.institution_id=v_inst),
 'courses',coalesce((select jsonb_agg(to_jsonb(x) order by x.course_code) from (
 select c.code course_code,c.name course_name,cr.total_score,cr.letter_grade,cr.grade_point,cr.passed,round(avg(cr2.total_score),2) class_average,round(cr.total_score-avg(cr2.total_score),2) difference_from_class,ap.name academic_period
 from public.course_results cr join public.course_offerings co on co.id=cr.course_offering_id join public.courses c on c.id=co.course_id join public.academic_periods ap on ap.id=co.academic_period_id join public.course_results cr2 on cr2.course_offering_id=co.id and cr2.result_status in ('submitted','approved','published')
 where cr.institution_id=v_inst and cr.student_id=p_student_id and cr.result_status in ('submitted','approved','published')
 group by c.code,c.name,cr.total_score,cr.letter_grade,cr.grade_point,cr.passed,ap.name) x),'[]'::jsonb),
 'attendance',(select jsonb_build_object('sessions',count(*),'present',count(*) filter(where sa.attendance_status in ('present','late')),'rate',round(count(*) filter(where sa.attendance_status in ('present','late'))*100.0/nullif(count(*),0),1)) from public.student_attendance sa where sa.institution_id=v_inst and sa.student_id=p_student_id));
end $$;
create or replace function public.unimis_bulk_approve_course_results(p_course_offering_ids uuid[],p_note text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid; v_id uuid; v_count int:=0; v_fail numeric; v_pass numeric; v_spread numeric;
begin
 select iu.institution_id into v_inst from public.unimis_effective_memberships116 iu join public.roles r on r.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active'
 and lower(coalesce(r.code,r.name)) in ('owner','registrar','superadmin','super_admin','exams_officer','examinations_officer') limit 1;
 if v_inst is null then raise exception 'Examinations approval access required'; end if;
 foreach v_id in array p_course_offering_ids loop
   select count(*) filter(where not coalesce(passed,false))*100.0/nullif(count(*),0),
          count(*) filter(where passed)*100.0/nullif(count(*),0),
          max(total_score)-min(total_score)
   into v_fail,v_pass,v_spread from public.course_results
   where institution_id=v_inst and course_offering_id=v_id and result_status='submitted';
   if coalesce(v_fail,0)>=40 or coalesce(v_pass,0)>=95 or coalesce(v_spread,0)>=50 then
      raise exception 'Bulk approval stopped: offering % has a review exception and requires individual review',v_id;
   end if;
   update public.course_results set result_status='approved',approved_by=auth.uid(),approved_at=now(),updated_at=now()
   where institution_id=v_inst and course_offering_id=v_id and result_status='submitted';
   if found then v_count:=v_count+1; end if;
 end loop;
 return jsonb_build_object('approved_courses',v_count);
end $$;
create or replace function public.unimis_save_grading_scheme(p_scheme jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid; v_id uuid; b jsonb;
begin
 select iu.institution_id into v_inst from public.unimis_effective_memberships116 iu
 join public.roles r on r.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active' and r.code in ('owner','exam_officer')
 order by iu.is_primary desc limit 1;
 if v_inst is null then raise exception 'Academic administration access required'; end if;

 if coalesce((p_scheme->>'is_default')::boolean,false) then
   update public.grading_schemes set is_default=false where institution_id=v_inst;
 end if;

 v_id=nullif(p_scheme->>'id','')::uuid;
 if v_id is null then
   insert into public.grading_schemes(institution_id,name,code,gpa_scale,is_default,status)
   values(v_inst,p_scheme->>'name',upper(p_scheme->>'code'),coalesce((p_scheme->>'gpa_scale')::numeric,4),
          coalesce((p_scheme->>'is_default')::boolean,false),'active')
   returning id into v_id;
 else
   update public.grading_schemes set name=p_scheme->>'name',code=upper(p_scheme->>'code'),
    gpa_scale=coalesce((p_scheme->>'gpa_scale')::numeric,gpa_scale),
    is_default=coalesce((p_scheme->>'is_default')::boolean,false),updated_at=now()
   where id=v_id and institution_id=v_inst;
 end if;

 delete from public.grade_bands where grading_scheme_id=v_id;
 for b in select * from jsonb_array_elements(coalesce(p_scheme->'bands','[]'::jsonb))
 loop
   insert into public.grade_bands(institution_id,grading_scheme_id,letter_grade,min_score,max_score,grade_point,classification,is_pass)
   values(v_inst,v_id,b->>'letter_grade',(b->>'min_score')::numeric,(b->>'max_score')::numeric,
          (b->>'grade_point')::numeric,nullif(b->>'classification',''),coalesce((b->>'is_pass')::boolean,true));
 end loop;
 return jsonb_build_object('ok',true,'id',v_id);
end $$;
create or replace function public.unimis_record_expense(p_expense jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid; v_id uuid;
begin
 select iu.institution_id into v_inst from public.unimis_effective_memberships116 iu join public.roles r on r.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active' and r.code in ('owner','finance_officer') order by iu.is_primary desc limit 1;
 if v_inst is null then raise exception 'Finance access required'; end if;
 insert into public.finance_expenses(institution_id,expense_date,description,amount,currency_code,payment_method,payee,reference,created_by)
 values(v_inst,coalesce((p_expense->>'expense_date')::date,current_date),p_expense->>'description',(p_expense->>'amount')::numeric,
        coalesce(nullif(p_expense->>'currency_code',''),'GHS'),coalesce(nullif(p_expense->>'payment_method',''),'cash'),
        nullif(p_expense->>'payee',''),nullif(p_expense->>'reference',''),auth.uid()) returning id into v_id;
 insert into public.finance_ledger_entries(institution_id,source_type,source_id,reference,description,account_code,account_name,debit,credit,currency_code)
 values(v_inst,'expense',v_id,p_expense->>'reference',p_expense->>'description','EXP','Operating Expenses',(p_expense->>'amount')::numeric,0,coalesce(nullif(p_expense->>'currency_code',''),'GHS'));
 return jsonb_build_object('ok',true,'id',v_id);
end $$;
create or replace function public.unimis_save_grading_assignment(p_assignment jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid; v_scope text; v_scheme uuid; v_programme uuid; v_course uuid; v_id uuid;
begin
 select iu.institution_id into v_inst
 from public.unimis_effective_memberships116 iu join public.roles r on r.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active' and r.code in ('owner','exam_officer')
 order by iu.is_primary desc limit 1;
 if v_inst is null then raise exception 'Academic administration access required'; end if;

 v_scope:=p_assignment->>'scope_type';
 v_scheme:=(p_assignment->>'grading_scheme_id')::uuid;
 v_programme:=nullif(p_assignment->>'programme_id','')::uuid;
 v_course:=nullif(p_assignment->>'course_id','')::uuid;

 if not exists(select 1 from public.grading_schemes where id=v_scheme and institution_id=v_inst) then
   raise exception 'Invalid grading scheme';
 end if;

 if v_scope='programme' then
   if v_programme is null then raise exception 'Programme is required'; end if;
   update public.grading_scheme_assignments set is_active=false,updated_at=now()
    where institution_id=v_inst and scope_type='programme' and programme_id=v_programme and is_active;
   insert into public.grading_scheme_assignments(institution_id,grading_scheme_id,scope_type,programme_id,created_by)
   values(v_inst,v_scheme,'programme',v_programme,auth.uid()) returning id into v_id;
 elsif v_scope='course' then
   if v_course is null then raise exception 'Course is required'; end if;
   update public.grading_scheme_assignments set is_active=false,updated_at=now()
    where institution_id=v_inst and scope_type='course' and course_id=v_course and is_active;
   insert into public.grading_scheme_assignments(institution_id,grading_scheme_id,scope_type,course_id,created_by)
   values(v_inst,v_scheme,'course',v_course,auth.uid()) returning id into v_id;
 else
   raise exception 'scope_type must be programme or course';
 end if;
 return jsonb_build_object('ok',true,'id',v_id);
end $$;
create or replace function public.unimis_delete_grading_assignment(p_assignment_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid;
begin
 select iu.institution_id into v_inst
 from public.unimis_effective_memberships116 iu join public.roles r on r.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active' and r.code in ('owner','exam_officer')
 order by iu.is_primary desc limit 1;
 if v_inst is null then raise exception 'Academic administration access required'; end if;
 update public.grading_scheme_assignments set is_active=false,updated_at=now()
 where id=p_assignment_id and institution_id=v_inst;
 return jsonb_build_object('ok',true);
end $$;
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r cross join public.permissions p
where r.code='registrar' and (p.module in ('admissions','students','academics','results') or p.code in ('reports.view','attendance.view','attendance.manage'))
on conflict do nothing;
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r cross join public.permissions p
where r.code='exam_officer' and p.code in ('results.view','results.approve','reports.view','academics.view','courses.view','students.view')
on conflict do nothing;

commit;
notify pgrst,'reload schema';
