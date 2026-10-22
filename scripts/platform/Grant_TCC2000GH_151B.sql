\set ON_ERROR_STOP on
\set email151 'tcc2000gh@gmail.com'
begin;
select set_config('unimis.operator_email151',lower(btrim(:'email151')),true);
do $$declare v_user uuid;begin
 if current_user not in('postgres','supabase_admin') then raise exception 'Protected database operator session required';end if;
 select id into v_user from auth.users where lower(email)=current_setting('unimis.operator_email151');
 if v_user is null then raise exception 'Create the separate Auth account first; no platform access was granted';end if;
 if exists(select 1 from public.institution_users where user_id=v_user) then raise exception 'This account has school memberships. Use a separate technical account, not a school Owner/Admin/Registrar';end if;
 insert into public.unimis_platform_operators116(user_id,active) values(v_user,true) on conflict(user_id) do update set active=true;
 insert into public.unimis_technical_events151(actor,action,reference,note) values(v_user,'protected_platform_provisioning',current_setting('unimis.operator_email151'),'Platform access provisioned through a protected database session; technical account remains separate from school roles.');
end $$;
commit;
select u.email,'Platform Superadmin / Technical Operator' as protected_role from auth.users u join public.unimis_platform_operators116 p on p.user_id=u.id and p.active where lower(u.email)=lower(btrim(:'email151'));
