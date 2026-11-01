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
     and not (v_old_code='owner' and old.status='pending' and new.status='active' and auth.uid()=new.user_id and exists(select 1 from public.unimis_institution_onboarding155 o join auth.users u on u.id=new.user_id where o.institution_id=new.institution_id and lower(o.owner_email)=lower(u.email) and o.owner_status='invitation_sent'))
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


