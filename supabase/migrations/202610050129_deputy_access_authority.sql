-- A Deputy is a revocable approval delegation, never an Owner membership.
insert into public.roles(name,code,is_system_role,is_active)
select 'Deputy Access Authority','deputy_access_authority',true,true
where not exists(select 1 from public.roles where code='deputy_access_authority' and institution_id is null);
create table if not exists public.unimis_deputies129(
 institution_user_id uuid primary key references public.institution_users(id) on delete restrict,
 active boolean not null default true,appointed_by uuid not null references auth.users(id),
 reason text not null,updated_at timestamptz not null default now());
create table if not exists public.unimis_deputy_events129(
 id uuid primary key default gen_random_uuid(),institution_id uuid not null references public.institutions(id),
 actor uuid not null references auth.users(id),target_user_id uuid not null references auth.users(id),
 action text not null,reason text not null,created_at timestamptz not null default now());
alter table public.unimis_deputies129 enable row level security;
alter table public.unimis_deputy_events129 enable row level security;
revoke all on public.unimis_deputies129,public.unimis_deputy_events129 from public,anon,authenticated;
create or replace function public.unimis_is_deputy129(p_inst uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.unimis_deputies129 d join public.institution_users m on m.id=d.institution_user_id
 where d.active and m.status='active' and m.user_id=auth.uid() and m.institution_id=p_inst
 and exists(select 1 from public.roles where code='deputy_access_authority' and institution_id is null and is_active))
$$;
revoke all on function public.unimis_is_deputy129(uuid) from public;
grant execute on function public.unimis_is_deputy129(uuid) to authenticated;
create or replace function public.unimis_deputy_workspace129(p_inst uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare is_owner boolean:=public.unimis_is_access_authority116(p_inst);
begin
 if not(is_owner or public.unimis_is_deputy129(p_inst)) then raise exception 'Access authority required';end if;
 return jsonb_build_object('owner',is_owner,
 'users',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'user_id',m.user_id,'name',coalesce(p.display_name,u.email),'email',u.email,'role',r.code,'status',m.status,'deputy',coalesce(d.active,false)) order by u.email)
 from public.institution_users m join public.roles r on r.id=m.role_id join auth.users u on u.id=m.user_id left join public.profiles p on p.id=m.user_id left join public.unimis_deputies129 d on d.institution_user_id=m.id where m.institution_id=p_inst),'[]'::jsonb),
 'requests',coalesce((select jsonb_agg(to_jsonb(q)||jsonb_build_object('role_name',r.name,'target_email',u.email,'requester_email',a.email,'reviewer_email',reviewer.email) order by q.created_at desc)
 from public.unimis_access_requests116 q join public.roles r on r.id=q.role_id left join auth.users u on u.id=q.target_user_id left join auth.users a on a.id=q.requested_by left join auth.users reviewer on reviewer.id=q.reviewed_by where q.institution_id=p_inst),'[]'::jsonb),
 'history',coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at desc) from public.unimis_deputy_events129 e where e.institution_id=p_inst),'[]'::jsonb));
end $$;
revoke all on function public.unimis_deputy_workspace129(uuid) from public;
grant execute on function public.unimis_deputy_workspace129(uuid) to authenticated;
create or replace function public.unimis_appoint_deputy129(p_member uuid,p_active boolean,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.institution_users; code text;
begin
 select * into m from public.institution_users where id=p_member for update;
 if m.id is null or not public.unimis_is_access_authority116(m.institution_id) then raise exception 'Only the Owner can appoint or revoke a Deputy';end if;
 if m.user_id=auth.uid() then raise exception 'You cannot appoint yourself';end if;
 if p_active is null or length(trim(coalesce(p_reason,'')))<10 then raise exception 'Appointment or revocation reason must have at least 10 characters';end if;
 select r.code into code from public.roles r where r.id=m.role_id and r.is_active;
 if p_active and (m.status<>'active' or code is null or code in ('owner','auditor','student','parent','superadmin','super_admin','platform_superadmin','deputy_access_authority')
 or exists(select 1 from public.unimis_additional_roles116 a join public.roles r on r.id=a.role_id where a.institution_user_id=m.id and r.code in ('auditor','owner','superadmin','super_admin','platform_superadmin'))
 or exists(select 1 from public.unimis_platform_operators116 op where op.user_id=m.user_id and op.active)) then raise exception 'Choose an active ordinary staff account';end if;
 insert into public.unimis_deputies129(institution_user_id,active,appointed_by,reason)
 values(m.id,p_active,auth.uid(),trim(p_reason)) on conflict(institution_user_id) do update set active=excluded.active,appointed_by=excluded.appointed_by,reason=excluded.reason,updated_at=now();
 insert into public.unimis_deputy_events129(institution_id,actor,target_user_id,action,reason) values(m.institution_id,auth.uid(),m.user_id,case when p_active then 'appoint_deputy' else 'revoke_deputy' end,trim(p_reason));
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.unimis_appoint_deputy129(uuid,boolean,text) from public;
grant execute on function public.unimis_appoint_deputy129(uuid,boolean,text) to authenticated;
create or replace function public.unimis_reactivate_staff129(p_member uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.institution_users; code text;
begin
 select * into m from public.institution_users where id=p_member for update;
 if m.id is null or not(public.unimis_is_access_authority116(m.institution_id) or public.unimis_is_deputy129(m.institution_id)) then raise exception 'Access authority required';end if;
 if m.user_id=auth.uid() then raise exception 'You cannot reactivate yourself';end if;
 if length(trim(coalesce(p_reason,'')))<10 then raise exception 'Explain the reactivation (at least 10 characters)';end if;
 select r.code into code from public.roles r where r.id=m.role_id;
 if code in ('owner','superadmin','super_admin','platform_superadmin','deputy_access_authority','student','parent') or exists(select 1 from public.unimis_deputies129 d where d.institution_user_id=m.id and d.active) then raise exception 'Protected authority or student account';end if;
 if m.status not in ('inactive','suspended') then raise exception 'Only inactive or suspended staff accounts can be reactivated';end if;
 update public.institution_users set status='active',updated_at=now() where id=m.id;
 insert into public.unimis_deputy_events129(institution_id,actor,target_user_id,action,reason) values(m.institution_id,auth.uid(),m.user_id,'reactivate_staff',trim(p_reason));
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.unimis_reactivate_staff129(uuid,text) from public;
grant execute on function public.unimis_reactivate_staff129(uuid,text) to authenticated;

create or replace function public.unimis_review_access116(p_request uuid,p_approve boolean,p_note text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare req public.unimis_access_requests116; m public.institution_users; v_code text;
begin
 select * into req from public.unimis_access_requests116 where id=p_request for update;
 if req.id is null then raise exception 'Access request not found'; end if;
 if not (public.unimis_is_access_authority116(req.institution_id) or public.unimis_is_deputy129(req.institution_id)) then raise exception 'Only the school approval authority can decide access requests'; end if;
 if auth.uid()=req.requested_by or auth.uid()=req.target_user_id or exists(select 1 from auth.users u where u.id=auth.uid() and lower(u.email)=req.email) then raise exception 'You cannot approve your own request or access'; end if;
 if not public.unimis_is_access_authority116(req.institution_id) and exists(
 select 1 from public.institution_users x join public.roles r on r.id=x.role_id
 where x.institution_id=req.institution_id and x.user_id=req.target_user_id
 and (r.code in ('owner','superadmin','super_admin','platform_superadmin','deputy_access_authority') or exists(select 1 from public.unimis_deputies129 d where d.institution_user_id=x.id and d.active))) then raise exception 'Deputies cannot change authority accounts';end if;
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

create or replace function public.unimis_access_role_valid116(p_inst uuid,p_role uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.roles r where r.id=p_role and r.is_active
 and (r.institution_id is null or r.institution_id=p_inst)
 and r.code not in ('owner','superadmin','super_admin','platform_superadmin','deputy_access_authority','student','parent'))
$$;

create or replace function public.unimis_guard_membership116()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_code text; v_old_code text; v_email text;
begin
 if tg_op in ('UPDATE','DELETE') and exists(select 1 from public.unimis_deputies129 d where d.institution_user_id=old.id and d.active) and auth.uid() is not null and not public.unimis_is_access_authority116(old.institution_id) then raise exception 'Only the Owner can change a Deputy account';end if;
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
   if new.status='active' and old.status not in ('active','pending') and v_old_code not in ('student','parent','staff') and auth.uid() is not null and not (public.unimis_is_access_authority116(new.institution_id) or public.unimis_is_deputy129(new.institution_id)) then raise exception 'Only the school authority can reactivate privileged accounts'; end if;
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

create or replace function public.unimis_guard_role_definition116()
returns trigger language plpgsql security definer set search_path='' as $$
declare inst uuid; v_code text; v_perm text;
begin
 if tg_table_name='roles' then
  if tg_op='INSERT' then v_code:=new.code; else v_code:=old.code; end if;
  if auth.uid() is not null and v_code in ('owner','superadmin','super_admin','platform_superadmin','deputy_access_authority') then raise exception 'Protected authority roles cannot be edited in school user management'; end if;
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

create or replace function public.unimis_my_deputy_roles129()
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('institution_id',m.institution_id,'role_id',r.id,'role',jsonb_build_object('id',r.id,'name',r.name,'code',r.code,'is_active',r.is_active))),'[]'::jsonb)
 from public.unimis_deputies129 d join public.institution_users m on m.id=d.institution_user_id
 join public.roles r on r.code='deputy_access_authority' and r.institution_id is null and r.is_active
 where d.active and m.status='active' and m.user_id=auth.uid()
$$;
revoke all on function public.unimis_my_deputy_roles129() from public;
grant execute on function public.unimis_my_deputy_roles129() to authenticated;
