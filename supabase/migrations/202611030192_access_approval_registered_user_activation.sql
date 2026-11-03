-- Build 192: approved invitation auto-activates an already registered Auth user.
-- Production schema: public.
create or replace function public.unimis_review_access116(p_request uuid,p_approve boolean,p_note text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare req public.unimis_access_requests116; m public.institution_users; v_code text; v_auth_user uuid;
begin
 select * into req from public.unimis_access_requests116 where id=p_request for update;
 if req.id is null then raise exception 'Access request not found'; end if;
 if not (public.unimis_is_access_authority116(req.institution_id) or public.unimis_is_deputy129(req.institution_id)) then raise exception 'Only the school approval authority can decide access requests'; end if;
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
  else
   select u.id into v_auth_user from auth.users u where lower(u.email)=lower(req.email) and u.email_confirmed_at is not null limit 1;
   if v_auth_user is not null and exists(select 1 from public.institution_users x where x.institution_id=req.institution_id and x.user_id=v_auth_user) then raise exception 'This registered user is already a member of the institution; use a role-change request instead'; end if;
  end if;
 end if;
 update public.unimis_access_requests116 set status=case when p_approve then 'approved' else 'rejected' end,reviewed_by=auth.uid(),reviewed_at=now(),review_note=trim(p_note) where id=req.id;
 if p_approve and req.action='primary_role' then
  update public.institution_users set role_id=req.role_id,updated_at=now() where id=m.id;
 elsif p_approve and req.action='add_role' then
  insert into public.unimis_additional_roles116(institution_user_id,role_id,request_id,granted_by) values(m.id,req.role_id,req.id,auth.uid());
 elsif p_approve and req.action='remove_role' then
  delete from public.unimis_additional_roles116 where institution_user_id=m.id and role_id=req.role_id;
 elsif p_approve and req.action='invite' and v_auth_user is not null then
  insert into public.institution_users(institution_id,user_id,role_id,status,is_primary) values(req.institution_id,v_auth_user,req.role_id,'active',true);
 end if;
 if p_approve and (req.action<>'invite' or v_auth_user is not null) then update public.unimis_access_requests116 set status='executed' where id=req.id; end if;
 return jsonb_build_object('ok',true,'status',case when not p_approve then 'rejected' when req.action='invite' and v_auth_user is null then 'approved' else 'executed' end,'registered_user_activated',coalesce(req.action='invite' and v_auth_user is not null,false));
end $$;
revoke all on function public.unimis_review_access116(uuid,boolean,text) from public;
grant execute on function public.unimis_review_access116(uuid,boolean,text) to authenticated;
notify pgrst, 'reload schema';
