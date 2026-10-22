-- Run in local Supabase Studio SQL Editor after creating a dedicated Auth user.
-- Replace the email below with YOUR technical operator email. No password is embedded.
-- A platform operator account must not also be a school officer account.
begin;
do $$
declare operator_email text:='REPLACE_WITH_YOUR_PLATFORM_EMAIL'; operator_id uuid; matches integer;
begin
 if operator_email='REPLACE_WITH_YOUR_PLATFORM_EMAIL' then raise exception 'Replace the placeholder with the dedicated Auth account email'; end if;
 select count(*),min(id::text)::uuid into matches,operator_id from auth.users where lower(email)=lower(trim(operator_email)) and email_confirmed_at is not null;
 if matches<>1 then raise exception 'Create exactly one dedicated Auth account for this email first'; end if;
 if exists(select 1 from public.institution_users where user_id=operator_id) then raise exception 'This account has school memberships. Create a separate technical account'; end if;
 insert into public.unimis_platform_operators116(user_id,active) values(operator_id,true) on conflict(user_id) do update set active=true;
end $$;
commit;
