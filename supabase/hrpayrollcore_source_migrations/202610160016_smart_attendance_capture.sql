-- Package 005b: Smart Attendance Capture (rotating QR token + optional GPS geofence)
create extension if not exists pgcrypto;

create table if not exists public.hr_attendance_sites(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete cascade,
 code text not null,
 name text not null,
 latitude numeric(10,7),
 longitude numeric(10,7),
 radius_meters integer not null default 150 check(radius_meters between 20 and 5000),
 gps_required boolean not null default false,
 qr_enabled boolean not null default true,
 active boolean not null default true,
 created_at timestamptz not null default now(),
 unique(tenant_id,code),
 check(not gps_required or (latitude is not null and longitude is not null))
);
create table if not exists public.hr_attendance_qr_tokens(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete cascade,
 site_id uuid not null references public.hr_attendance_sites(id) on delete cascade,
 token_hash text not null,
 expires_at timestamptz not null,
 revoked_at timestamptz,
 created_by uuid default auth.uid(),
 created_at timestamptz not null default now()
);
create table if not exists public.hr_attendance_capture_events(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete cascade,
 employee_id uuid not null references public.hr_employees(id) on delete cascade,
 site_id uuid references public.hr_attendance_sites(id) on delete set null,
 attendance_id uuid references public.hr_attendance_records(id) on delete set null,
 event_type text not null check(event_type in ('check_in','check_out')),
 captured_at timestamptz not null default now(),
 capture_method text not null default 'qr' check(capture_method in ('qr','gps','nfc','biometric','api')),
 latitude numeric(10,7),longitude numeric(10,7),
 distance_meters numeric(10,2),gps_verified boolean,
 token_id uuid references public.hr_attendance_qr_tokens(id) on delete set null,
 created_by uuid default auth.uid()
);
alter table public.hr_attendance_records add column if not exists attendance_site_id uuid references public.hr_attendance_sites(id) on delete set null;
alter table public.hr_attendance_records add column if not exists gps_verified boolean;
alter table public.hr_attendance_records add column if not exists check_in_source text;
alter table public.hr_attendance_records add column if not exists check_out_source text;

alter table public.hr_attendance_sites enable row level security;
alter table public.hr_attendance_qr_tokens enable row level security;
alter table public.hr_attendance_capture_events enable row level security;
drop policy if exists tenant_member_all on public.hr_attendance_sites;
create policy tenant_member_all on public.hr_attendance_sites for all using(public.is_tenant_member(tenant_id)) with check(public.is_tenant_member(tenant_id));
drop policy if exists tenant_member_all on public.hr_attendance_qr_tokens;
create policy tenant_member_all on public.hr_attendance_qr_tokens for all using(public.is_tenant_member(tenant_id)) with check(public.is_tenant_member(tenant_id));
drop policy if exists tenant_member_all on public.hr_attendance_capture_events;
create policy tenant_member_all on public.hr_attendance_capture_events for all using(public.is_tenant_member(tenant_id)) with check(public.is_tenant_member(tenant_id));

create or replace function public.hr_distance_meters(lat1 numeric,lon1 numeric,lat2 numeric,lon2 numeric)
returns numeric language sql immutable as $$
 select 6371000 * 2 * asin(sqrt(power(sin(radians((lat2-lat1)/2)),2)+cos(radians(lat1))*cos(radians(lat2))*power(sin(radians((lon2-lon1)/2)),2)));
$$;

create or replace function public.hr_create_attendance_qr_token(p_tenant uuid,p_site uuid,p_valid_minutes integer default 5)
returns jsonb language plpgsql security definer set search_path=public as $$
declare raw_token text; exp timestamptz; tid uuid;
begin
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if p_valid_minutes not between 1 and 30 then raise exception 'Token validity must be 1-30 minutes'; end if;
 if not exists(select 1 from hr_attendance_sites where id=p_site and tenant_id=p_tenant and active and qr_enabled) then raise exception 'Active QR-enabled site not found'; end if;
 update hr_attendance_qr_tokens set revoked_at=now() where tenant_id=p_tenant and site_id=p_site and revoked_at is null and expires_at>now();
 raw_token=upper(substr(encode(gen_random_bytes(12),'hex'),1,20)); exp=now()+make_interval(mins=>p_valid_minutes);
 insert into hr_attendance_qr_tokens(tenant_id,site_id,token_hash,expires_at) values(p_tenant,p_site,encode(digest(raw_token,'sha256'),'hex'),exp) returning id into tid;
 return jsonb_build_object('token',raw_token,'expires_at',exp,'token_id',tid);
end $$;

create or replace function public.hr_capture_attendance(p_tenant uuid,p_employee uuid,p_site uuid,p_token text,p_action text,p_latitude numeric default null,p_longitude numeric default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare s hr_attendance_sites%rowtype; tok hr_attendance_qr_tokens%rowtype; rec hr_attendance_records%rowtype; dist numeric; nowts timestamptz:=now(); d date:=current_date; verified boolean:=null; method text:='qr';
begin
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if p_action not in ('check_in','check_out') then raise exception 'Invalid attendance action'; end if;
 if not exists(select 1 from hr_employees where id=p_employee and tenant_id=p_tenant and employment_status='active') then raise exception 'Active employee not found'; end if;
 select * into s from hr_attendance_sites where id=p_site and tenant_id=p_tenant and active;
 if s.id is null then raise exception 'Attendance site not found'; end if;
 select * into tok from hr_attendance_qr_tokens where tenant_id=p_tenant and site_id=p_site and token_hash=encode(digest(upper(trim(p_token)),'sha256'),'hex') and revoked_at is null and expires_at>=now() order by created_at desc limit 1;
 if tok.id is null then raise exception 'QR token is invalid or expired'; end if;
 if s.gps_required then
   if p_latitude is null or p_longitude is null then raise exception 'GPS location is required at this attendance site'; end if;
   dist=public.hr_distance_meters(s.latitude,s.longitude,p_latitude,p_longitude); verified=dist<=s.radius_meters; method='gps';
   if not verified then raise exception 'Outside attendance site geofence (% m away; allowed radius % m)',round(dist),s.radius_meters; end if;
 end if;
 select * into rec from hr_attendance_records where tenant_id=p_tenant and employee_id=p_employee and work_date=d for update;
 if rec.id is null then
   insert into hr_attendance_records(tenant_id,employee_id,work_date,status,capture_method,attendance_site_id,gps_verified,check_in,check_in_source,latitude,longitude,notes)
   values(p_tenant,p_employee,d,'present',method,p_site,verified,case when p_action='check_in' then nowts end,case when p_action='check_in' then method end,p_latitude,p_longitude,'Smart attendance capture')
   returning * into rec;
 end if;
 if p_action='check_in' then
   if rec.status in ('on_leave','holiday','off_day') then raise exception 'Check-in blocked because attendance status is %',replace(rec.status,'_',' '); end if;
   if rec.check_in is not null then raise exception 'Employee has already checked in today'; end if;
   update hr_attendance_records set check_in=nowts,status='present',capture_method=method,attendance_site_id=p_site,gps_verified=verified,check_in_source=method,latitude=p_latitude,longitude=p_longitude where id=rec.id returning * into rec;
 else
   if rec.check_in is null then raise exception 'Employee must check in before checking out'; end if;
   if rec.check_out is not null then raise exception 'Employee has already checked out today'; end if;
   update hr_attendance_records set check_out=nowts,capture_method=method,attendance_site_id=coalesce(attendance_site_id,p_site),gps_verified=coalesce(verified,gps_verified),check_out_source=method where id=rec.id returning * into rec;
 end if;
 insert into hr_attendance_capture_events(tenant_id,employee_id,site_id,attendance_id,event_type,captured_at,capture_method,latitude,longitude,distance_meters,gps_verified,token_id)
 values(p_tenant,p_employee,p_site,rec.id,p_action,nowts,method,p_latitude,p_longitude,dist,verified,tok.id);
 return jsonb_build_object('ok',true,'message',case when p_action='check_in' then 'Check-in recorded successfully.' else 'Check-out recorded successfully.' end,'attendance_id',rec.id,'gps_verified',verified,'distance_meters',dist);
end $$;

grant execute on function public.hr_create_attendance_qr_token(uuid,uuid,integer) to authenticated;
grant execute on function public.hr_capture_attendance(uuid,uuid,uuid,text,text,numeric,numeric) to authenticated;
create index if not exists idx_attendance_sites_tenant on public.hr_attendance_sites(tenant_id,active);
create index if not exists idx_attendance_tokens_site_expiry on public.hr_attendance_qr_tokens(tenant_id,site_id,expires_at desc);
create index if not exists idx_attendance_events_employee_time on public.hr_attendance_capture_events(tenant_id,employee_id,captured_at desc);
