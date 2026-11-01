-- UniMIS 156: secure first-Owner invitation and activation
alter table public.unimis_institution_onboarding155
 drop constraint if exists unimis_institution_onboarding155_owner_status_check;
alter table public.unimis_institution_onboarding155
 add constraint unimis_institution_onboarding155_owner_status_check
 check(owner_status in('not_set','awaiting_registration','invitation_sent','assigned'));

create or replace function public.unimis_prepare_platform_owner156(p_inst uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare o public.unimis_institution_onboarding155; r uuid;
begin
 if not public.unimis_is_platform_operator116() then raise exception 'Protected platform operator required'; end if;
 select * into o from public.unimis_institution_onboarding155 where institution_id=p_inst for update;
 if o.institution_id is null or nullif(o.owner_email,'') is null then raise exception 'Pending institution Owner not found'; end if;
 if o.owner_status='assigned' then raise exception 'Institution Owner is already assigned'; end if;
 select id into r from public.roles where institution_id=p_inst and code='owner' and is_active limit 1;
 if r is null then raise exception 'Institution Owner role is not configured'; end if;
 update public.unimis_institution_onboarding155 set owner_status='invitation_sent',updated_at=now() where institution_id=p_inst;
 return jsonb_build_object('institution_id',p_inst,'email',lower(o.owner_email),'first_name',o.owner_first_name,'last_name',o.owner_last_name,'role_id',r);
end $$;
revoke all on function public.unimis_prepare_platform_owner156(uuid) from public;
grant execute on function public.unimis_prepare_platform_owner156(uuid) to authenticated;

create or replace function public.unimis_guard_membership116()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_code text; v_old_code text; v_email text;
begin
 if tg_op in ('UPDATE','DELETE') and exists(select 1 from public.unimis_deputies129 d where d.institution_user_id=old.id and d.active)
 and auth.uid() is not null and not public.unimis_is_access_authority116(old.institution_id) then raise exception 'Only the Owner can change a Deputy account'; end if;
 if tg_op='DELETE' then
  if exists(select 1 from public.roles where id=old.role_id and code in ('owner','superadmin','super_admin','platform_superadmin')) then raise exception 'Protected authority account cannot be deleted'; end if;
  if auth.uid()=old.user_id then raise exception 'You cannot delete your own membership'; end if; return old;
 end if;
 if tg_op='UPDATE' then
  if new.user_id is distinct from old.user_id or new.institution_id is distinct from old.institution_id then raise exception 'Membership identity cannot be changed'; end if;
  select code into v_old_code from public.roles where id=old.role_id;
  if v_old_code in ('owner','superadmin','super_admin','platform_superadmin') and (new.role_id is distinct from old.role_id or new.status is distinct from old.status)
     and not (v_old_code='owner' and old.status='pending' and new.status='active' and auth.uid()=new.user_id)
  then raise exception 'Protected authority account'; end if;
  if new.role_id is not distinct from old.role_id then return new; end if;
 end if;
 if exists(select 1 from public.unimis_platform_operators116 where user_id=new.user_id and active) then raise exception 'Platform operator accounts cannot receive school memberships'; end if;
 select code into v_code from public.roles where id=new.role_id and is_active and (institution_id is null or institution_id=new.institution_id);
 if v_code is null then raise exception 'Valid school role required'; end if;
 if tg_op='INSERT' and v_code='owner' and (
   public.unimis_is_platform_operator116()
   or (auth.uid() is null and exists(
     select 1 from auth.users u join public.unimis_institution_onboarding155 o
       on o.institution_id=new.institution_id and lower(o.owner_email)=lower(u.email)
     where u.id=new.user_id and o.owner_status='invitation_sent'))
 ) then return new; end if;
 if tg_op='INSERT' and v_code in ('student','parent','staff') then return new; end if;
 if auth.uid() is null and session_user in ('postgres','supabase_admin') then return new; end if;
 if tg_op='UPDATE' and exists(select 1 from public.unimis_access_requests116 q where q.institution_id=new.institution_id and q.action='primary_role' and q.target_user_id=new.user_id and q.role_id=new.role_id and q.previous_role_id=old.role_id and q.status='approved' and q.reviewed_by=auth.uid() and q.reviewed_by<>q.requested_by and q.reviewed_by<>new.user_id) then return new; end if;
 select lower(email) into v_email from auth.users where id=new.user_id;
 if tg_op='INSERT' and exists(select 1 from public.user_invitations i join public.unimis_access_requests116 q on q.id=i.approval_request_id where i.institution_id=new.institution_id and lower(i.email)=v_email and i.role_id=new.role_id and i.status='pending' and i.expires_at>now() and q.status='approved' and q.reviewed_by<>q.requested_by) then return new; end if;
 raise exception 'Role assignment requires an independently approved request';
end $$;

create or replace function public.handle_unimis_invited_auth_user()
returns trigger language plpgsql security definer set search_path='' as $$
declare inv public.user_invitations; o public.unimis_institution_onboarding155; rid uuid; iid uuid;
begin
 if new.invited_at is null then return new; end if;

 if coalesce(new.raw_user_meta_data->>'platform_owner','')='true' then
  iid:=nullif(new.raw_user_meta_data->>'institution_id','')::uuid;
  select * into o from public.unimis_institution_onboarding155 where institution_id=iid and lower(owner_email)=lower(new.email) and owner_status='invitation_sent';
  select id into rid from public.roles where institution_id=iid and code='owner' and is_active;
  if o.institution_id is not null and rid is not null then
   insert into public.profiles(id,email,first_name,last_name,display_name,status)
   values(new.id,lower(new.email),o.owner_first_name,o.owner_last_name,coalesce(nullif(concat_ws(' ',o.owner_first_name,o.owner_last_name),''),new.email),'active')
   on conflict(id) do update set email=excluded.email;
   insert into public.institution_users(institution_id,user_id,role_id,status,is_primary)
   values(iid,new.id,rid,'pending',true) on conflict(institution_id,user_id) do nothing;
  end if;
  return new;
 end if;

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
declare u auth.users; inv public.user_invitations; o public.unimis_institution_onboarding155; rid uuid;
begin
 select * into u from auth.users where id=auth.uid();
 if u.id is null or u.email_confirmed_at is null then return false; end if;

 select * into o from public.unimis_institution_onboarding155
 where lower(owner_email)=lower(u.email) and owner_status='invitation_sent' order by created_at desc limit 1 for update;
 if o.institution_id is not null then
  select id into rid from public.roles where institution_id=o.institution_id and code='owner' and is_active limit 1;
  if rid is not null then
   insert into public.institution_users(institution_id,user_id,role_id,status,is_primary)
   values(o.institution_id,u.id,rid,'active',true)
   on conflict(institution_id,user_id) do update set role_id=excluded.role_id,status='active',is_primary=true,updated_at=now();
   update public.unimis_institution_onboarding155 set owner_status='assigned',updated_at=now() where institution_id=o.institution_id;
  end if;
 end if;

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
