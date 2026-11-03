-- 005d1: make QR token crypto functions resolvable on local/hosted Supabase.
-- Supabase commonly installs pgcrypto in the extensions schema, while older/local
-- projects may expose it from public. Keep both schemas on the function search path.
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create or replace function public.hr_create_attendance_qr_token(
  p_tenant uuid,
  p_site uuid,
  p_valid_minutes integer default 5
)
returns jsonb
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  raw_token text;
  exp timestamptz;
  tid uuid;
begin
  if not public.is_tenant_member(p_tenant) then
    raise exception 'Tenant access denied';
  end if;
  if p_valid_minutes not between 1 and 30 then
    raise exception 'Token validity must be 1-30 minutes';
  end if;
  if not exists(
    select 1 from public.hr_attendance_sites
    where id=p_site and tenant_id=p_tenant and active and qr_enabled
  ) then
    raise exception 'Active QR-enabled site not found';
  end if;

  update public.hr_attendance_qr_tokens
     set revoked_at=now()
   where tenant_id=p_tenant
     and site_id=p_site
     and revoked_at is null
     and expires_at>now();

  raw_token=upper(substr(encode(gen_random_bytes(12),'hex'),1,20));
  exp=now()+make_interval(mins=>p_valid_minutes);

  insert into public.hr_attendance_qr_tokens(tenant_id,site_id,token_hash,expires_at)
  values(p_tenant,p_site,encode(digest(raw_token,'sha256'),'hex'),exp)
  returning id into tid;

  return jsonb_build_object('token',raw_token,'expires_at',exp,'token_id',tid);
end
$$;

grant execute on function public.hr_create_attendance_qr_token(uuid,uuid,integer) to authenticated;

-- The capture function also uses digest(), so ensure the same extension search path.
alter function public.hr_capture_attendance(uuid,uuid,uuid,text,text,numeric,numeric)
  set search_path=public,extensions;

notify pgrst, 'reload schema';
