-- 005e1 Passwordless employee attendance: one-time phone activation + permanent site QR
alter table public.hr_attendance_sites add column if not exists permanent_qr_token text;
create unique index if not exists uq_attendance_site_permanent_qr on public.hr_attendance_sites(permanent_qr_token) where permanent_qr_token is not null;

create table if not exists public.hr_attendance_device_activations(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 employee_id uuid not null references public.hr_employees(id) on delete cascade, token_hash text not null unique,
 expires_at timestamptz not null, redeemed_at timestamptz, created_by uuid default auth.uid(), created_at timestamptz not null default now());
create table if not exists public.hr_attendance_devices(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 employee_id uuid not null references public.hr_employees(id) on delete cascade, credential_hash text not null unique,
 label text default 'Employee phone', active boolean not null default true, activated_at timestamptz not null default now(),
 last_used_at timestamptz, revoked_at timestamptz, created_at timestamptz not null default now());
alter table public.hr_attendance_device_activations enable row level security;
alter table public.hr_attendance_devices enable row level security;
drop policy if exists tenant_member_all on public.hr_attendance_device_activations;
create policy tenant_member_all on public.hr_attendance_device_activations for all using(public.is_tenant_member(tenant_id)) with check(public.is_tenant_member(tenant_id));
drop policy if exists tenant_member_all on public.hr_attendance_devices;
create policy tenant_member_all on public.hr_attendance_devices for all using(public.is_tenant_member(tenant_id)) with check(public.is_tenant_member(tenant_id));

create or replace function public.hr_get_or_create_permanent_site_qr(p_tenant uuid,p_site uuid) returns jsonb
language plpgsql security definer set search_path=public,extensions as $$
declare t text;
begin
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select permanent_qr_token into t from public.hr_attendance_sites where id=p_site and tenant_id=p_tenant and active;
 if not found then raise exception 'Attendance site not found'; end if;
 if t is null then t=encode(extensions.gen_random_bytes(24),'hex'); update public.hr_attendance_sites set permanent_qr_token=t where id=p_site; end if;
 return jsonb_build_object('token',t);
end $$;
create or replace function public.hr_regenerate_permanent_site_qr(p_tenant uuid,p_site uuid) returns void
language plpgsql security definer set search_path=public,extensions as $$ begin
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 update public.hr_attendance_sites set permanent_qr_token=encode(extensions.gen_random_bytes(24),'hex') where id=p_site and tenant_id=p_tenant;
 if not found then raise exception 'Attendance site not found'; end if;
end $$;

create or replace function public.hr_create_attendance_device_activation(p_tenant uuid,p_employee uuid) returns jsonb
language plpgsql security definer set search_path=public,extensions as $$
declare raw text; exp timestamptz:=now()+interval '30 minutes'; n text;
begin
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select concat(first_name,' ',last_name) into n from public.hr_employees where id=p_employee and tenant_id=p_tenant and employment_status='active';
 if n is null then raise exception 'Active employee not found'; end if;
 update public.hr_attendance_device_activations set expires_at=now() where tenant_id=p_tenant and employee_id=p_employee and redeemed_at is null and expires_at>now();
 raw=encode(extensions.gen_random_bytes(24),'hex');
 insert into public.hr_attendance_device_activations(tenant_id,employee_id,token_hash,expires_at) values(p_tenant,p_employee,encode(extensions.digest(raw,'sha256'),'hex'),exp);
 return jsonb_build_object('activation_token',raw,'expires_at',exp,'employee_name',n);
end $$;

create or replace function public.hr_redeem_attendance_device_activation(p_activation_token text) returns jsonb
language plpgsql security definer set search_path=public,extensions as $$
declare a public.hr_attendance_device_activations%rowtype; raw text; n text;
begin
 select * into a from public.hr_attendance_device_activations where token_hash=encode(extensions.digest(trim(p_activation_token),'sha256'),'hex') and redeemed_at is null and expires_at>=now() for update;
 if a.id is null then raise exception 'Activation QR is invalid, expired or already used'; end if;
 raw=encode(extensions.gen_random_bytes(32),'hex');
 insert into public.hr_attendance_devices(tenant_id,employee_id,credential_hash) values(a.tenant_id,a.employee_id,encode(extensions.digest(raw,'sha256'),'hex'));
 update public.hr_attendance_device_activations set redeemed_at=now() where id=a.id;
 select concat(first_name,' ',last_name) into n from public.hr_employees where id=a.employee_id;
 return jsonb_build_object('tenant_id',a.tenant_id,'employee_name',n,'device_credential',raw);
end $$;

create or replace function public.hr_public_attendance_context(p_tenant uuid,p_site uuid,p_site_token text,p_device_credential text) returns jsonb
language plpgsql security definer set search_path=public,extensions as $$
declare s public.hr_attendance_sites%rowtype; d public.hr_attendance_devices%rowtype; e public.hr_employees%rowtype; r public.hr_attendance_records%rowtype; act text;
begin
 select * into s from public.hr_attendance_sites where id=p_site and tenant_id=p_tenant and active and qr_enabled and permanent_qr_token=p_site_token;
 if s.id is null then raise exception 'Workplace QR is invalid or has been revoked'; end if;
 select * into d from public.hr_attendance_devices where tenant_id=p_tenant and credential_hash=encode(extensions.digest(trim(p_device_credential),'sha256'),'hex') and active and revoked_at is null;
 if d.id is null then raise exception 'This phone is not activated for attendance'; end if;
 select * into e from public.hr_employees where id=d.employee_id and tenant_id=p_tenant and employment_status='active'; if e.id is null then raise exception 'Employee is not active'; end if;
 select * into r from public.hr_attendance_records where tenant_id=p_tenant and employee_id=e.id and work_date=current_date;
 act=case when r.check_in is null then 'check_in' when r.check_out is null then 'check_out' else 'complete' end;
 return jsonb_build_object('employee',jsonb_build_object('name',concat(e.first_name,' ',e.last_name),'employee_no',e.employee_no),'site',jsonb_build_object('name',s.name,'gps_required',s.gps_required),'action',act,'complete',(act='complete'));
end $$;

create or replace function public.hr_public_device_attendance(p_tenant uuid,p_site uuid,p_site_token text,p_device_credential text,p_latitude numeric default null,p_longitude numeric default null) returns jsonb
language plpgsql security definer set search_path=public,extensions as $$
declare s public.hr_attendance_sites%rowtype; d public.hr_attendance_devices%rowtype; e public.hr_employees%rowtype; r public.hr_attendance_records%rowtype; dist numeric; verified boolean:=null; nowts timestamptz:=now(); act text;
begin
 select * into s from public.hr_attendance_sites where id=p_site and tenant_id=p_tenant and active and qr_enabled and permanent_qr_token=p_site_token; if s.id is null then raise exception 'Workplace QR is invalid or revoked'; end if;
 select * into d from public.hr_attendance_devices where tenant_id=p_tenant and credential_hash=encode(extensions.digest(trim(p_device_credential),'sha256'),'hex') and active and revoked_at is null; if d.id is null then raise exception 'Phone attendance activation is invalid or revoked'; end if;
 select * into e from public.hr_employees where id=d.employee_id and tenant_id=p_tenant and employment_status='active'; if e.id is null then raise exception 'Employee is not active'; end if;
 if s.gps_required then if p_latitude is null or p_longitude is null then raise exception 'GPS location is required'; end if; dist=public.hr_distance_meters(s.latitude,s.longitude,p_latitude,p_longitude); verified=dist<=s.radius_meters; if not verified then raise exception 'Outside attendance site geofence (% m away; allowed radius % m)',round(dist),s.radius_meters; end if; end if;
 select * into r from public.hr_attendance_records where tenant_id=p_tenant and employee_id=e.id and work_date=current_date for update;
 if r.id is null then insert into public.hr_attendance_records(tenant_id,employee_id,work_date,status,capture_method,attendance_site_id,gps_verified,check_in,check_in_source,latitude,longitude,notes) values(p_tenant,e.id,current_date,'present',case when s.gps_required then 'gps' else 'qr' end,p_site,verified,nowts,case when s.gps_required then 'gps' else 'qr' end,p_latitude,p_longitude,'Passwordless employee attendance') returning * into r; act='check_in';
 elsif r.check_in is null then update public.hr_attendance_records set check_in=nowts,status='present',attendance_site_id=p_site,gps_verified=verified,latitude=p_latitude,longitude=p_longitude where id=r.id returning * into r; act='check_in';
 elsif r.check_out is null then update public.hr_attendance_records set check_out=nowts,gps_verified=coalesce(verified,gps_verified),check_out_source=case when s.gps_required then 'gps' else 'qr' end where id=r.id returning * into r; act='check_out';
 else raise exception 'Attendance is already complete for today'; end if;
 insert into public.hr_attendance_capture_events(tenant_id,employee_id,site_id,attendance_id,event_type,captured_at,capture_method,latitude,longitude,distance_meters,gps_verified) values(p_tenant,e.id,p_site,r.id,act,nowts,case when s.gps_required then 'gps' else 'qr' end,p_latitude,p_longitude,dist,verified);
 update public.hr_attendance_devices set last_used_at=now() where id=d.id;
 return jsonb_build_object('message',case when act='check_in' then 'Checked in successfully.' else 'Checked out successfully.' end,'action',act,'gps_verified',verified,'distance_meters',dist);
end $$;

grant execute on function public.hr_get_or_create_permanent_site_qr(uuid,uuid) to authenticated;
grant execute on function public.hr_regenerate_permanent_site_qr(uuid,uuid) to authenticated;
grant execute on function public.hr_create_attendance_device_activation(uuid,uuid) to authenticated;
grant execute on function public.hr_redeem_attendance_device_activation(text) to anon,authenticated;
grant execute on function public.hr_public_attendance_context(uuid,uuid,text,text) to anon,authenticated;
grant execute on function public.hr_public_device_attendance(uuid,uuid,text,text,numeric,numeric) to anon,authenticated;
