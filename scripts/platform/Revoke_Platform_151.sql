\set ON_ERROR_STOP on
\prompt 'Technical account email to revoke: ' email151
begin;
select set_config('unimis.operator_email151',lower(btrim(:'email151')),true);
do $$declare v_user uuid;begin
 if current_user not in('postgres','supabase_admin') then raise exception 'Protected database operator session required';end if;
 select u.id into v_user from auth.users u join public.unimis_platform_operators116 p on p.user_id=u.id where lower(u.email)=current_setting('unimis.operator_email151');
 if v_user is null then raise exception 'Platform account not found';end if;
 update public.unimis_platform_operators116 set active=false where user_id=v_user;
 update public.unimis_support151 set status='revoked',expires_at=null where operator_id=v_user and status in('pending','approved');
 insert into public.unimis_technical_events151(actor,action,reference,note) values(v_user,'protected_platform_revocation',current_setting('unimis.operator_email151'),'Protected database session revoked platform access and support scopes.');
end $$;
commit;
