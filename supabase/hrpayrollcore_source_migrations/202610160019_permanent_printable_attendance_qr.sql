-- 005e Permanent/revocable site QR for printed attendance posters.
create extension if not exists pgcrypto with schema extensions;

create or replace function public.hr_create_permanent_attendance_qr(
  p_tenant uuid,
  p_site uuid
) returns jsonb
language plpgsql security definer
set search_path=public,extensions
as $$
declare raw_token text; exp timestamptz; tid uuid;
begin
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if not exists(select 1 from public.hr_attendance_sites where id=p_site and tenant_id=p_tenant and active and qr_enabled) then
   raise exception 'Active QR-enabled site not found';
 end if;
 -- One permanent printed QR per site. Generating a replacement revokes the old one.
 update public.hr_attendance_qr_tokens set revoked_at=now()
 where tenant_id=p_tenant and site_id=p_site and revoked_at is null;
 raw_token=upper(substr(encode(gen_random_bytes(18),'hex'),1,28));
 -- Existing capture engine requires expires_at. Use a far-future date; revocation is the real control.
 exp=now()+interval '20 years';
 insert into public.hr_attendance_qr_tokens(tenant_id,site_id,token_hash,expires_at)
 values(p_tenant,p_site,encode(digest(raw_token,'sha256'),'hex'),exp)
 returning id into tid;
 return jsonb_build_object('token',raw_token,'expires_at',exp,'token_id',tid,'mode','permanent');
end $$;
grant execute on function public.hr_create_permanent_attendance_qr(uuid,uuid) to authenticated;
notify pgrst, 'reload schema';
