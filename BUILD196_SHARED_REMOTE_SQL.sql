-- Build 196: Profile/name onboarding installer fix for shared Supabase SQL Editor.
-- The SQL Editor session is postgres but may start with current_role=authenticated.
-- RESET ROLE restores the session owner before creating/replacing schema objects.
reset role;

-- Production schema: unimis.
create or replace function unimis.unimis_review_access116(p_request uuid,p_approve boolean,p_note text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare req unimis.unimis_access_requests116; m unimis.institution_users; v_code text; v_auth_user uuid;
begin
 select * into req from unimis.unimis_access_requests116 where id=p_request for update;
 if req.id is null then raise exception 'Access request not found'; end if;
 if not (unimis.unimis_is_access_authority116(req.institution_id) or unimis.unimis_is_deputy129(req.institution_id)) then raise exception 'Only the school approval authority can decide access requests'; end if;
 if auth.uid()=req.requested_by or auth.uid()=req.target_user_id or exists(select 1 from auth.users u where u.id=auth.uid() and lower(u.email)=req.email) then raise exception 'You cannot approve your own request or access'; end if;
 if req.status<>'pending' then raise exception 'This request has already been decided'; end if;
 if length(trim(coalesce(p_note,'')))<5 then raise exception 'A decision note is required'; end if;
 if not unimis.unimis_access_role_valid116(req.institution_id,req.role_id) then raise exception 'The requested role is no longer available'; end if;
 if p_approve then
  select code into v_code from unimis.roles where id=req.role_id;
  if req.action<>'invite' then
   select * into m from unimis.institution_users where institution_id=req.institution_id and user_id=req.target_user_id for update;
   if m.id is null or m.role_id is distinct from req.previous_role_id then raise exception 'The membership changed; submit a fresh request'; end if;
   if exists(select 1 from unimis.roles where id=m.role_id and code in ('owner','student','parent','superadmin','super_admin','platform_superadmin')) then raise exception 'Protected account'; end if;
   if req.action<>'remove_role' and (v_code='auditor' and exists(select 1 from unimis.unimis_additional_roles116 where institution_user_id=m.id) or v_code<>'auditor' and exists(select 1 from unimis.unimis_additional_roles116 a join unimis.roles r on r.id=a.role_id where a.institution_user_id=m.id and r.code='auditor') or req.action='add_role' and (v_code='auditor' or exists(select 1 from unimis.roles where id=m.role_id and code='auditor'))) then raise exception 'Auditor access cannot be combined with operational roles'; end if;
  else
   select u.id into v_auth_user from auth.users u where lower(u.email)=lower(req.email) and u.email_confirmed_at is not null limit 1;
   if v_auth_user is not null and exists(select 1 from unimis.institution_users x where x.institution_id=req.institution_id and x.user_id=v_auth_user) then raise exception 'This registered user is already a member of the institution; use a role-change request instead'; end if;
  end if;
 end if;
 update unimis.unimis_access_requests116 set status=case when p_approve then 'approved' else 'rejected' end,reviewed_by=auth.uid(),reviewed_at=now(),review_note=trim(p_note) where id=req.id;
 if p_approve and req.action='primary_role' then
  update unimis.institution_users set role_id=req.role_id,updated_at=now() where id=m.id;
 elsif p_approve and req.action='add_role' then
  insert into unimis.unimis_additional_roles116(institution_user_id,role_id,request_id,granted_by) values(m.id,req.role_id,req.id,auth.uid());
 elsif p_approve and req.action='remove_role' then
  delete from unimis.unimis_additional_roles116 where institution_user_id=m.id and role_id=req.role_id;
 elsif p_approve and req.action='invite' and v_auth_user is not null then
  insert into unimis.profiles(id,first_name,middle_name,last_name,display_name,status,updated_at)
  values(v_auth_user,req.first_name,req.middle_name,req.last_name,trim(concat_ws(' ',req.first_name,req.middle_name,req.last_name)),'active',now())
  on conflict(id) do update set
    first_name=coalesce(nullif(trim(excluded.first_name),''),unimis.profiles.first_name),
    middle_name=coalesce(nullif(trim(excluded.middle_name),''),unimis.profiles.middle_name),
    last_name=coalesce(nullif(trim(excluded.last_name),''),unimis.profiles.last_name),
    display_name=coalesce(nullif(trim(excluded.display_name),''),unimis.profiles.display_name),
    status='active',updated_at=now();
  insert into unimis.institution_users(institution_id,user_id,role_id,status,is_primary) values(req.institution_id,v_auth_user,req.role_id,'active',true);
 end if;
 if p_approve and (req.action<>'invite' or v_auth_user is not null) then update unimis.unimis_access_requests116 set status='executed' where id=req.id; end if;
 return jsonb_build_object('ok',true,'status',case when not p_approve then 'rejected' when req.action='invite' and v_auth_user is null then 'approved' else 'executed' end,'registered_user_activated',coalesce(req.action='invite' and v_auth_user is not null,false));
end $$;
-- Backfill profiles for already executed/approved staff invitations where Auth membership exists.
insert into unimis.profiles(id,first_name,middle_name,last_name,display_name,status,updated_at)
select distinct on (u.id) u.id, r.first_name, r.middle_name, r.last_name,
       nullif(trim(concat_ws(' ',r.first_name,r.middle_name,r.last_name)),''), 'active', now()
from unimis.unimis_access_requests116 r
join auth.users u on lower(u.email)=lower(r.email)
join unimis.institution_users iu on iu.user_id=u.id and iu.institution_id=r.institution_id
where r.action='invite' and r.status in ('approved','executed')
  and (r.first_name is not null or r.last_name is not null)
order by u.id,r.created_at desc
on conflict(id) do update set
 first_name=coalesce(nullif(trim(excluded.first_name),''),unimis.profiles.first_name),
 middle_name=coalesce(nullif(trim(excluded.middle_name),''),unimis.profiles.middle_name),
 last_name=coalesce(nullif(trim(excluded.last_name),''),unimis.profiles.last_name),
 display_name=coalesce(nullif(trim(excluded.display_name),''),unimis.profiles.display_name),
 status='active',updated_at=now();

revoke all on function unimis.unimis_review_access116(uuid,boolean,text) from public;
grant execute on function unimis.unimis_review_access116(uuid,boolean,text) to authenticated;
notify pgrst, 'reload schema';
