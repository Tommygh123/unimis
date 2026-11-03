-- CONTINUATION: UniMIS Build 172 HR/Payroll repair
set search_path=unimis,public;

-- SOURCE 202610160019_permanent_printable_attendance_qr.sql
-- 005e Permanent/revocable site QR for printed attendance posters.
create extension if not exists pgcrypto with schema extensions;

create or replace function unimis.hr_create_permanent_attendance_qr(
  p_tenant uuid,
  p_site uuid
) returns jsonb
language plpgsql security definer
set search_path=unimis,extensions
as $$
declare raw_token text; exp timestamptz; tid uuid;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if not exists(select 1 from unimis.hrc_hr_attendance_sites where id=p_site and tenant_id=p_tenant and active and qr_enabled) then
   raise exception 'Active QR-enabled site not found';
 end if;
 -- One permanent printed QR per site. Generating a replacement revokes the old one.
 update unimis.hrc_hr_attendance_qr_tokens set revoked_at=now()
 where tenant_id=p_tenant and site_id=p_site and revoked_at is null;
 raw_token=upper(substr(encode(gen_random_bytes(18),'hex'),1,28));
 -- Existing capture engine requires expires_at. Use a far-future date; revocation is the real control.
 exp=now()+interval '20 years';
 insert into unimis.hrc_hr_attendance_qr_tokens(tenant_id,site_id,token_hash,expires_at)
 values(p_tenant,p_site,encode(digest(raw_token,'sha256'),'hex'),exp)
 returning id into tid;
 return jsonb_build_object('token',raw_token,'expires_at',exp,'token_id',tid,'mode','permanent');
end $$;
grant execute on function unimis.hr_create_permanent_attendance_qr(uuid,uuid) to authenticated;
notify pgrst, 'reload schema';


-- SOURCE 202610160020_passwordless_employee_attendance.sql
-- 005e1 Passwordless employee attendance: one-time phone activation + permanent site QR
alter table unimis.hrc_hr_attendance_sites add column if not exists permanent_qr_token text;
create unique index if not exists uq_attendance_site_permanent_qr on unimis.hrc_hr_attendance_sites(permanent_qr_token) where permanent_qr_token is not null;

create table if not exists unimis.hrc_hr_attendance_device_activations(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hrc_hr_employees(id) on delete cascade, token_hash text not null unique,
 expires_at timestamptz not null, redeemed_at timestamptz, created_by uuid default auth.uid(), created_at timestamptz not null default now());
create table if not exists unimis.hrc_hr_attendance_devices(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hrc_hr_employees(id) on delete cascade, credential_hash text not null unique,
 label text default 'Employee phone', active boolean not null default true, activated_at timestamptz not null default now(),
 last_used_at timestamptz, revoked_at timestamptz, created_at timestamptz not null default now());
alter table unimis.hrc_hr_attendance_device_activations enable row level security;
alter table unimis.hrc_hr_attendance_devices enable row level security;
drop policy if exists tenant_member_all on unimis.hrc_hr_attendance_device_activations;
create policy tenant_member_all on unimis.hrc_hr_attendance_device_activations for all using(unimis.is_tenant_member(tenant_id)) with check(unimis.is_tenant_member(tenant_id));
drop policy if exists tenant_member_all on unimis.hrc_hr_attendance_devices;
create policy tenant_member_all on unimis.hrc_hr_attendance_devices for all using(unimis.is_tenant_member(tenant_id)) with check(unimis.is_tenant_member(tenant_id));

create or replace function unimis.hr_get_or_create_permanent_site_qr(p_tenant uuid,p_site uuid) returns jsonb
language plpgsql security definer set search_path=unimis,extensions as $$
declare t text;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select permanent_qr_token into t from unimis.hrc_hr_attendance_sites where id=p_site and tenant_id=p_tenant and active;
 if not found then raise exception 'Attendance site not found'; end if;
 if t is null then t=encode(extensions.gen_random_bytes(24),'hex'); update unimis.hrc_hr_attendance_sites set permanent_qr_token=t where id=p_site; end if;
 return jsonb_build_object('token',t);
end $$;
create or replace function unimis.hr_regenerate_permanent_site_qr(p_tenant uuid,p_site uuid) returns void
language plpgsql security definer set search_path=unimis,extensions as $$ begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 update unimis.hrc_hr_attendance_sites set permanent_qr_token=encode(extensions.gen_random_bytes(24),'hex') where id=p_site and tenant_id=p_tenant;
 if not found then raise exception 'Attendance site not found'; end if;
end $$;

create or replace function unimis.hr_create_attendance_device_activation(p_tenant uuid,p_employee uuid) returns jsonb
language plpgsql security definer set search_path=unimis,extensions as $$
declare raw text; exp timestamptz:=now()+interval '30 minutes'; n text;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select concat(first_name,' ',last_name) into n from unimis.hrc_hr_employees where id=p_employee and tenant_id=p_tenant and employment_status='active';
 if n is null then raise exception 'Active employee not found'; end if;
 update unimis.hrc_hr_attendance_device_activations set expires_at=now() where tenant_id=p_tenant and employee_id=p_employee and redeemed_at is null and expires_at>now();
 raw=encode(extensions.gen_random_bytes(24),'hex');
 insert into unimis.hrc_hr_attendance_device_activations(tenant_id,employee_id,token_hash,expires_at) values(p_tenant,p_employee,encode(extensions.digest(raw,'sha256'),'hex'),exp);
 return jsonb_build_object('activation_token',raw,'expires_at',exp,'employee_name',n);
end $$;

create or replace function unimis.hr_redeem_attendance_device_activation(p_activation_token text) returns jsonb
language plpgsql security definer set search_path=unimis,extensions as $$
declare a unimis.hrc_hr_attendance_device_activations%rowtype; raw text; n text;
begin
 select * into a from unimis.hrc_hr_attendance_device_activations where token_hash=encode(extensions.digest(trim(p_activation_token),'sha256'),'hex') and redeemed_at is null and expires_at>=now() for update;
 if a.id is null then raise exception 'Activation QR is invalid, expired or already used'; end if;
 raw=encode(extensions.gen_random_bytes(32),'hex');
 insert into unimis.hrc_hr_attendance_devices(tenant_id,employee_id,credential_hash) values(a.tenant_id,a.employee_id,encode(extensions.digest(raw,'sha256'),'hex'));
 update unimis.hrc_hr_attendance_device_activations set redeemed_at=now() where id=a.id;
 select concat(first_name,' ',last_name) into n from unimis.hrc_hr_employees where id=a.employee_id;
 return jsonb_build_object('tenant_id',a.tenant_id,'employee_name',n,'device_credential',raw);
end $$;

create or replace function unimis.hr_public_attendance_context(p_tenant uuid,p_site uuid,p_site_token text,p_device_credential text) returns jsonb
language plpgsql security definer set search_path=unimis,extensions as $$
declare s unimis.hrc_hr_attendance_sites%rowtype; d unimis.hrc_hr_attendance_devices%rowtype; e unimis.hrc_hr_employees%rowtype; r unimis.hrc_hr_attendance_records%rowtype; act text;
begin
 select * into s from unimis.hrc_hr_attendance_sites where id=p_site and tenant_id=p_tenant and active and qr_enabled and permanent_qr_token=p_site_token;
 if s.id is null then raise exception 'Workplace QR is invalid or has been revoked'; end if;
 select * into d from unimis.hrc_hr_attendance_devices where tenant_id=p_tenant and credential_hash=encode(extensions.digest(trim(p_device_credential),'sha256'),'hex') and active and revoked_at is null;
 if d.id is null then raise exception 'This phone is not activated for attendance'; end if;
 select * into e from unimis.hrc_hr_employees where id=d.employee_id and tenant_id=p_tenant and employment_status='active'; if e.id is null then raise exception 'Employee is not active'; end if;
 select * into r from unimis.hrc_hr_attendance_records where tenant_id=p_tenant and employee_id=e.id and work_date=current_date;
 act=case when r.check_in is null then 'check_in' when r.check_out is null then 'check_out' else 'complete' end;
 return jsonb_build_object('employee',jsonb_build_object('name',concat(e.first_name,' ',e.last_name),'employee_no',e.employee_no),'site',jsonb_build_object('name',s.name,'gps_required',s.gps_required),'action',act,'complete',(act='complete'));
end $$;

create or replace function unimis.hr_public_device_attendance(p_tenant uuid,p_site uuid,p_site_token text,p_device_credential text,p_latitude numeric default null,p_longitude numeric default null) returns jsonb
language plpgsql security definer set search_path=unimis,extensions as $$
declare s unimis.hrc_hr_attendance_sites%rowtype; d unimis.hrc_hr_attendance_devices%rowtype; e unimis.hrc_hr_employees%rowtype; r unimis.hrc_hr_attendance_records%rowtype; dist numeric; verified boolean:=null; nowts timestamptz:=now(); act text;
begin
 select * into s from unimis.hrc_hr_attendance_sites where id=p_site and tenant_id=p_tenant and active and qr_enabled and permanent_qr_token=p_site_token; if s.id is null then raise exception 'Workplace QR is invalid or revoked'; end if;
 select * into d from unimis.hrc_hr_attendance_devices where tenant_id=p_tenant and credential_hash=encode(extensions.digest(trim(p_device_credential),'sha256'),'hex') and active and revoked_at is null; if d.id is null then raise exception 'Phone attendance activation is invalid or revoked'; end if;
 select * into e from unimis.hrc_hr_employees where id=d.employee_id and tenant_id=p_tenant and employment_status='active'; if e.id is null then raise exception 'Employee is not active'; end if;
 if s.gps_required then if p_latitude is null or p_longitude is null then raise exception 'GPS location is required'; end if; dist=unimis.hr_distance_meters(s.latitude,s.longitude,p_latitude,p_longitude); verified=dist<=s.radius_meters; if not verified then raise exception 'Outside attendance site geofence (% m away; allowed radius % m)',round(dist),s.radius_meters; end if; end if;
 select * into r from unimis.hrc_hr_attendance_records where tenant_id=p_tenant and employee_id=e.id and work_date=current_date for update;
 if r.id is null then insert into unimis.hrc_hr_attendance_records(tenant_id,employee_id,work_date,status,capture_method,attendance_site_id,gps_verified,check_in,check_in_source,latitude,longitude,notes) values(p_tenant,e.id,current_date,'present',case when s.gps_required then 'gps' else 'qr' end,p_site,verified,nowts,case when s.gps_required then 'gps' else 'qr' end,p_latitude,p_longitude,'Passwordless employee attendance') returning * into r; act='check_in';
 elsif r.check_in is null then update unimis.hrc_hr_attendance_records set check_in=nowts,status='present',attendance_site_id=p_site,gps_verified=verified,latitude=p_latitude,longitude=p_longitude where id=r.id returning * into r; act='check_in';
 elsif r.check_out is null then update unimis.hrc_hr_attendance_records set check_out=nowts,gps_verified=coalesce(verified,gps_verified),check_out_source=case when s.gps_required then 'gps' else 'qr' end where id=r.id returning * into r; act='check_out';
 else raise exception 'Attendance is already complete for today'; end if;
 insert into unimis.hrc_hr_attendance_capture_events(tenant_id,employee_id,site_id,attendance_id,event_type,captured_at,capture_method,latitude,longitude,distance_meters,gps_verified) values(p_tenant,e.id,p_site,r.id,act,nowts,case when s.gps_required then 'gps' else 'qr' end,p_latitude,p_longitude,dist,verified);
 update unimis.hrc_hr_attendance_devices set last_used_at=now() where id=d.id;
 return jsonb_build_object('message',case when act='check_in' then 'Checked in successfully.' else 'Checked out successfully.' end,'action',act,'gps_verified',verified,'distance_meters',dist);
end $$;

grant execute on function unimis.hr_get_or_create_permanent_site_qr(uuid,uuid) to authenticated;
grant execute on function unimis.hr_regenerate_permanent_site_qr(uuid,uuid) to authenticated;
grant execute on function unimis.hr_create_attendance_device_activation(uuid,uuid) to authenticated;
grant execute on function unimis.hr_redeem_attendance_device_activation(text) to anon,authenticated;
grant execute on function unimis.hr_public_attendance_context(uuid,uuid,text,text) to anon,authenticated;
grant execute on function unimis.hr_public_device_attendance(uuid,uuid,text,text,numeric,numeric) to anon,authenticated;


-- SOURCE 202610160021_hr_operations_performance_training_reports.sql
-- Package 006: HR Operations Completion - attendance controls, performance, training and DSS
alter table unimis.hrc_hr_attendance_records add column if not exists approval_status text not null default 'draft';
alter table unimis.hrc_hr_attendance_records add column if not exists approved_by uuid;
alter table unimis.hrc_hr_attendance_records add column if not exists approved_at timestamptz;
alter table unimis.hrc_hr_attendance_records add column if not exists correction_reason text;
alter table unimis.hrc_hr_attendance_records drop constraint if exists hr_attendance_records_approval_status_check;
alter table unimis.hrc_hr_attendance_records add constraint hr_attendance_records_approval_status_check check(approval_status in ('draft','submitted','approved','rejected'));

create table if not exists unimis.hrc_hr_performance_cycles(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 name text not null,cycle_type text not null default 'annual' check(cycle_type in ('annual','quarterly','probation','project','other')),
 start_date date not null,end_date date not null,status text not null default 'draft' check(status in ('draft','open','closed','archived')),
 created_by uuid default auth.uid(),created_at timestamptz not null default now(),check(end_date>=start_date)
);
create table if not exists unimis.hrc_hr_performance_reviews(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 cycle_id uuid not null references unimis.hrc_hr_performance_cycles(id) on delete cascade,employee_id uuid not null references unimis.hrc_hr_employees(id) on delete cascade,
 reviewer_employee_id uuid references unimis.hrc_hr_employees(id),status text not null default 'draft' check(status in ('draft','submitted','reviewed','completed','cancelled')),
 objective_score numeric(6,2),competency_score numeric(6,2),final_score numeric(6,2),final_rating text,employee_comments text,reviewer_comments text,development_needs text,
 submitted_at timestamptz,completed_at timestamptz,created_by uuid default auth.uid(),created_at timestamptz not null default now(),unique(tenant_id,cycle_id,employee_id)
);
create table if not exists unimis.hrc_hr_performance_objectives(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,review_id uuid not null references unimis.hrc_hr_performance_reviews(id) on delete cascade,
 title text not null,description text,weight numeric(6,2) not null default 0,target text,achievement text,score numeric(6,2),created_at timestamptz not null default now()
);
create table if not exists unimis.hrc_hr_performance_competencies(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,review_id uuid not null references unimis.hrc_hr_performance_reviews(id) on delete cascade,
 competency text not null,weight numeric(6,2) not null default 0,score numeric(6,2),comments text,created_at timestamptz not null default now()
);
create table if not exists unimis.hrc_hr_training_programs(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,code text not null,name text not null,
 provider text,venue text,start_date date,end_date date,cost numeric(14,2) not null default 0,currency text not null default 'GHS',status text not null default 'planned' check(status in ('planned','open','in_progress','completed','cancelled')),
 certificate_required boolean not null default false,certificate_valid_months integer,notes text,created_by uuid default auth.uid(),created_at timestamptz not null default now(),unique(tenant_id,code)
);
create table if not exists unimis.hrc_hr_training_enrollments(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,program_id uuid not null references unimis.hrc_hr_training_programs(id) on delete cascade,
 employee_id uuid not null references unimis.hrc_hr_employees(id) on delete cascade,source text not null default 'hr' check(source in ('hr','performance','employee','manager')),
 performance_review_id uuid references unimis.hrc_hr_performance_reviews(id) on delete set null,status text not null default 'nominated' check(status in ('nominated','approved','enrolled','attended','completed','failed','cancelled')),
 result text,score numeric(6,2),certificate_path text,certificate_no text,certificate_expiry date,completion_date date,created_by uuid default auth.uid(),created_at timestamptz not null default now(),unique(tenant_id,program_id,employee_id)
);

do $$ declare t text; begin foreach t in array array['hrc_hr_performance_cycles','hrc_hr_performance_reviews','hrc_hr_performance_objectives','hrc_hr_performance_competencies','hrc_hr_training_programs','hrc_hr_training_enrollments'] loop execute format('alter table unimis.%I enable row level security',t);execute format('drop policy if exists tenant_member_all on unimis.%I',t);execute format('create policy tenant_member_all on unimis.%I for all using (unimis.is_tenant_member(tenant_id)) with check (unimis.is_tenant_member(tenant_id))',t);end loop;end $$;

create or replace function unimis.hr_decide_attendance(p_tenant uuid,p_record uuid,p_decision text,p_reason text default null) returns jsonb language plpgsql security definer set search_path=unimis as $$
begin if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied';end if;if p_decision not in ('approved','rejected') then raise exception 'Invalid decision';end if;update hrc_hr_attendance_records set approval_status=p_decision,approved_by=auth.uid(),approved_at=now(),correction_reason=coalesce(p_reason,correction_reason) where tenant_id=p_tenant and id=p_record;if not found then raise exception 'Attendance record not found';end if;return jsonb_build_object('ok',true,'status',p_decision);end $$;
grant execute on function unimis.hr_decide_attendance(uuid,uuid,text,text) to authenticated;
create index if not exists idx_perf_review_tenant_employee on unimis.hrc_hr_performance_reviews(tenant_id,employee_id,created_at desc);
create index if not exists idx_training_enrol_tenant_employee on unimis.hrc_hr_training_enrollments(tenant_id,employee_id,created_at desc);


-- SOURCE 202610160022_hr_operational_depth_demo_seed.sql
-- Package 006c: HR operational depth + demonstration data
-- Attendance reporting remains sourced from hrc_hr_attendance_records/capture_events.

create table if not exists unimis.hrc_hr_performance_policies(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 name text not null, effective_from date not null default current_date, effective_to date, active boolean not null default true,
 objective_weight numeric(5,2) not null default 60, competency_weight numeric(5,2) not null default 30,
 attendance_conduct_weight numeric(5,2) not null default 10, satisfactory_score numeric(5,2) not null default 2.50,
 self_assessment text not null default 'optional' check(self_assessment in ('disabled','optional','required')),
 supervisor_required boolean not null default true, second_level_approval boolean not null default true,
 evidence_required boolean not null default true, rating_scale jsonb not null default '[{"min":4.5,"max":5,"label":"Outstanding"},{"min":3.5,"max":4.49,"label":"Exceeds Expectations"},{"min":2.5,"max":3.49,"label":"Meets Expectations"},{"min":1.5,"max":2.49,"label":"Needs Improvement"},{"min":1,"max":1.49,"label":"Unsatisfactory"}]'::jsonb,
 created_by uuid default auth.uid(), created_at timestamptz not null default now(), unique(tenant_id,name,effective_from),
 check(objective_weight+competency_weight+attendance_conduct_weight=100)
);
create table if not exists unimis.hrc_hr_performance_improvement_plans(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hrc_hr_employees(id) on delete cascade, review_id uuid references unimis.hrc_hr_performance_reviews(id) on delete set null,
 title text not null, objectives text not null, actions_support text, start_date date not null, review_date date not null,
 status text not null default 'open' check(status in ('open','on_track','extended','successfully_closed','unsuccessfully_closed')),
 outcome text, created_by uuid default auth.uid(), created_at timestamptz not null default now()
);
alter table unimis.hrc_hr_training_programs add column if not exists training_type text default 'professional_development';
alter table unimis.hrc_hr_training_programs add column if not exists purpose text;
alter table unimis.hrc_hr_training_programs add column if not exists objectives text;
alter table unimis.hrc_hr_training_programs add column if not exists delivery_mode text default 'in_person';
alter table unimis.hrc_hr_training_programs add column if not exists trainer text;
alter table unimis.hrc_hr_training_programs add column if not exists start_time time;
alter table unimis.hrc_hr_training_programs add column if not exists end_time time;
alter table unimis.hrc_hr_training_programs add column if not exists duration_hours numeric(7,2);
alter table unimis.hrc_hr_training_programs add column if not exists target_group text;
alter table unimis.hrc_hr_training_programs add column if not exists capacity integer;
alter table unimis.hrc_hr_training_programs add column if not exists mandatory boolean not null default false;
alter table unimis.hrc_hr_training_programs add column if not exists assessment_required boolean not null default false;
alter table unimis.hrc_hr_training_enrollments add column if not exists attendance_percent numeric(5,2);
alter table unimis.hrc_hr_training_enrollments add column if not exists feedback text;

do $$ declare t text; begin foreach t in array array['hrc_hr_performance_policies','hrc_hr_performance_improvement_plans'] loop execute format('alter table unimis.%I enable row level security',t);execute format('drop policy if exists tenant_member_all on unimis.%I',t);execute format('create policy tenant_member_all on unimis.%I for all using(unimis.is_tenant_member(tenant_id)) with check(unimis.is_tenant_member(tenant_id))',t);end loop;end $$;

-- Demonstration data: created per tenant only when enough employee records exist.
do $$
declare t record; e1 uuid; e2 uuid; e3 uuid; cyc uuid; rev uuid; prog1 uuid; prog2 uuid; s uuid;
begin
 for t in select id from unimis.hrc_tenants loop
  select id into e1 from unimis.hrc_hr_employees where tenant_id=t.id order by created_at limit 1 offset 0;
  select id into e2 from unimis.hrc_hr_employees where tenant_id=t.id order by created_at limit 1 offset 1;
  select id into e3 from unimis.hrc_hr_employees where tenant_id=t.id order by created_at limit 1 offset 2;
  if e1 is null then continue; end if;
  insert into unimis.hrc_hr_performance_policies(tenant_id,name,effective_from) values(t.id,'Standard Performance Policy',date_trunc('year',current_date)::date) on conflict do nothing;
  insert into unimis.hrc_hr_performance_cycles(tenant_id,name,cycle_type,start_date,end_date,status)
   values(t.id,'2026 Annual Performance Review','annual',date '2026-01-01',date '2026-12-31','open')
   on conflict do nothing;
  select id into cyc from unimis.hrc_hr_performance_cycles where tenant_id=t.id and name='2026 Annual Performance Review' limit 1;
  insert into unimis.hrc_hr_performance_reviews(tenant_id,cycle_id,employee_id,status,objective_score,competency_score,final_score,final_rating,reviewer_comments,development_needs,completed_at)
   values(t.id,cyc,e1,'completed',4.2,4.0,4.1,'Exceeds Expectations','Strong delivery and collaboration.','Advanced leadership and reporting skills.',now()-interval '10 days') on conflict do nothing;
  select id into rev from unimis.hrc_hr_performance_reviews where tenant_id=t.id and cycle_id=cyc and employee_id=e1;
  if rev is not null and not exists(select 1 from unimis.hrc_hr_performance_objectives where review_id=rev) then
   insert into unimis.hrc_hr_performance_objectives(tenant_id,review_id,title,description,weight,target,achievement,score) values
    (t.id,rev,'Service delivery','Improve turnaround time',60,'95% on-time completion','96% achieved',4.2);
   insert into unimis.hrc_hr_performance_competencies(tenant_id,review_id,competency,weight,score,comments) values
    (t.id,rev,'Teamwork and communication',40,4.0,'Consistently collaborates well.');
  end if;
  if e2 is not null then insert into unimis.hrc_hr_performance_reviews(tenant_id,cycle_id,employee_id,status,development_needs) values(t.id,cyc,e2,'submitted','Excel analytics and supervisory skills') on conflict do nothing; end if;

  insert into unimis.hrc_hr_training_programs(tenant_id,code,name,training_type,purpose,objectives,provider,trainer,venue,delivery_mode,start_date,end_date,start_time,end_time,duration_hours,target_group,capacity,cost,status,certificate_required,certificate_valid_months,mandatory,assessment_required)
   values(t.id,'TRN-LEAD-26','Supervisory Leadership Essentials','leadership','Prepare emerging supervisors for people-management responsibilities.','Coaching, delegation, feedback and team leadership.','Internal / External Facilitator','HR Development Facilitator','Main Training Room','in_person',current_date-20,current_date-19,'09:00','16:00',12,'Supervisors and high-potential staff',20,2500,'completed',true,24,false,true)
   on conflict(tenant_id,code) do nothing;
  select id into prog1 from unimis.hrc_hr_training_programs where tenant_id=t.id and code='TRN-LEAD-26';
  insert into unimis.hrc_hr_training_programs(tenant_id,code,name,training_type,purpose,objectives,provider,trainer,venue,delivery_mode,start_date,end_date,start_time,end_time,duration_hours,target_group,capacity,cost,status,certificate_required,mandatory,assessment_required)
   values(t.id,'TRN-SAFE-26','Workplace Safety Refresher','safety','Refresh workplace safety practices and incident prevention.','Hazard identification, reporting and emergency response.','Internal','Safety Officer','Conference Room','in_person',current_date+7,current_date+7,'09:00','13:00',4,'All staff',40,800,'planned',false,true,true)
   on conflict(tenant_id,code) do nothing;
  select id into prog2 from unimis.hrc_hr_training_programs where tenant_id=t.id and code='TRN-SAFE-26';
  insert into unimis.hrc_hr_training_enrollments(tenant_id,program_id,employee_id,source,status,result,score,attendance_percent,completion_date,certificate_no,certificate_expiry,feedback)
   values(t.id,prog1,e1,'performance','completed','Pass',86,100,current_date-19,'CERT-DEMO-001',current_date+interval '24 months','Useful practical leadership session.') on conflict do nothing;
  if e2 is not null then insert into unimis.hrc_hr_training_enrollments(tenant_id,program_id,employee_id,source,status) values(t.id,prog2,e2,'manager','nominated') on conflict do nothing; end if;

  select id into s from unimis.hrc_hr_attendance_sites where tenant_id=t.id and active order by created_at limit 1;
  -- ten-day attendance demonstration, preserving any existing real record via ON CONFLICT DO NOTHING.
  insert into unimis.hrc_hr_attendance_records(tenant_id,employee_id,work_date,check_in,check_out,status,capture_method,attendance_site_id,gps_verified,late_minutes,overtime_minutes,worked_minutes,approval_status,notes)
  values
   (t.id,e1,current_date-9,(current_date-9)+time '07:55',(current_date-9)+time '17:05','present','manual',s,true,0,5,550,'approved','Demo attendance'),
   (t.id,e1,current_date-8,(current_date-8)+time '08:22',(current_date-8)+time '17:00','late','manual',s,true,12,0,518,'approved','Demo late arrival'),
   (t.id,e1,current_date-7,(current_date-7)+time '07:58',(current_date-7)+time '18:10','present','manual',s,true,0,70,612,'approved','Demo overtime'),
   (t.id,e1,current_date-6,(current_date-6)+time '08:02',null,'present','manual',s,true,0,0,0,'submitted','Demo missing checkout')
  on conflict(tenant_id,employee_id,work_date) do nothing;
  if e2 is not null then
   insert into unimis.hrc_hr_attendance_records(tenant_id,employee_id,work_date,check_in,check_out,status,capture_method,attendance_site_id,gps_verified,late_minutes,overtime_minutes,worked_minutes,approval_status,notes) values
    (t.id,e2,current_date-9,(current_date-9)+time '08:04',(current_date-9)+time '17:03','present','manual',s,true,0,3,539,'approved','Demo attendance'),
    (t.id,e2,current_date-8,null,null,'absent','manual',s,null,0,0,0,'submitted','Demo unexplained absence'),
    (t.id,e2,current_date-7,(current_date-7)+time '08:35',(current_date-7)+time '17:00','late','manual',s,true,25,0,505,'approved','Demo late arrival')
   on conflict(tenant_id,employee_id,work_date) do nothing;
  end if;
  if e3 is not null then
   insert into unimis.hrc_hr_attendance_records(tenant_id,employee_id,work_date,status,capture_method,attendance_site_id,worked_minutes,approval_status,notes) values
    (t.id,e3,current_date-9,'on_leave','api',s,0,'approved','Demo approved leave'),
    (t.id,e3,current_date-8,'half_day','manual',s,240,'approved','Demo half day')
   on conflict(tenant_id,employee_id,work_date) do nothing;
  end if;
 end loop;
end $$;
create index if not exists idx_perf_policy_tenant_active on unimis.hrc_hr_performance_policies(tenant_id,active,effective_from desc);
create index if not exists idx_pip_tenant_employee on unimis.hrc_hr_performance_improvement_plans(tenant_id,employee_id,created_at desc);


-- SOURCE 202610160023_configurable_ghana_payroll_2026.sql
-- HRPayrollCore 007: Configurable Ghana statutory payroll engine (effective-dated; not hard-coded in UI)
-- Official seed basis: GRA 2026 PAYE effective 2026-09-01; SSNIT/NPRA 3-tier pension framework and 2026 insurable earnings.

alter table unimis.hrc_payroll_profiles
 add column if not exists tax_residency text not null default 'resident',
 add column if not exists pension_tier1_enabled boolean not null default true,
 add column if not exists pension_tier2_enabled boolean not null default true,
 add column if not exists provident_fund_enabled boolean not null default false,
 add column if not exists provident_employee_rate numeric(8,4) not null default 0,
 add column if not exists provident_employer_rate numeric(8,4) not null default 0,
 add column if not exists provident_scheme_name text;

alter table unimis.hrc_payroll_run_employees
 add column if not exists taxable_income numeric(14,2) not null default 0,
 add column if not exists chargeable_income numeric(14,2) not null default 0,
 add column if not exists tier1_total numeric(14,2) not null default 0,
 add column if not exists tier2_total numeric(14,2) not null default 0,
 add column if not exists provident_employee numeric(14,2) not null default 0,
 add column if not exists provident_employer numeric(14,2) not null default 0,
 add column if not exists tax_relief numeric(14,2) not null default 0,
 add column if not exists employer_cost numeric(14,2) not null default 0;

alter table unimis.hrc_payroll_components
 add column if not exists tax_treatment text not null default 'graduated',
 add column if not exists pre_tax boolean not null default false,
 add column if not exists recurring boolean not null default true;

create table if not exists unimis.hrc_payroll_tax_bands(
 id uuid primary key default gen_random_uuid(), tenant_id uuid references unimis.hrc_tenants(id) on delete cascade,
 country_code text not null default 'GH', tax_year int not null, frequency text not null default 'monthly',
 band_order int not null, band_amount numeric(14,2), rate numeric(8,4) not null,
 effective_from date not null, effective_to date, active boolean not null default true,
 source_note text, unique(tenant_id,country_code,frequency,effective_from,band_order)
);
create table if not exists unimis.hrc_payroll_pension_rules(
 id uuid primary key default gen_random_uuid(), tenant_id uuid references unimis.hrc_tenants(id) on delete cascade,
 country_code text not null default 'GH', name text not null, effective_from date not null, effective_to date,
 employee_rate numeric(8,4) not null default 0, employer_rate numeric(8,4) not null default 0,
 tier1_total_rate numeric(8,4) not null default 0, tier2_total_rate numeric(8,4) not null default 0,
 minimum_insurable numeric(14,2), maximum_insurable numeric(14,2), provident_tax_relief_cap_rate numeric(8,4) not null default 0,
 active boolean not null default true, source_note text, unique(tenant_id,country_code,effective_from)
);
create table if not exists unimis.hrc_payroll_relief_types(
 id uuid primary key default gen_random_uuid(), tenant_id uuid references unimis.hrc_tenants(id) on delete cascade,
 country_code text not null default 'GH', code text not null, name text not null, calculation_type text not null default 'fixed_annual',
 annual_amount numeric(14,2), percent_rate numeric(8,4), max_units int, requires_approval boolean not null default true,
 active boolean not null default true, source_note text, unique(tenant_id,country_code,code)
);
create table if not exists unimis.hrc_payroll_employee_reliefs(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hrc_hr_employees(id) on delete cascade, relief_type_id uuid not null references unimis.hrc_payroll_relief_types(id),
 tax_year int not null, units int not null default 1, approved_annual_amount numeric(14,2), approved boolean not null default false,
 effective_from date not null, effective_to date, reference text, created_at timestamptz not null default now(),
 unique(employee_id,relief_type_id,tax_year)
);
create table if not exists unimis.hrc_payroll_adjustments(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hrc_hr_employees(id) on delete cascade, period_id uuid references unimis.hrc_payroll_periods(id) on delete cascade,
 adjustment_type text not null check(adjustment_type in ('earning','deduction','pre_tax_deduction','loan','arrears','overtime','unpaid_absence','bonus')),
 code text not null, description text not null, amount numeric(14,2) not null, taxable boolean not null default true,
 pensionable boolean not null default false, status text not null default 'approved' check(status in ('draft','pending','approved','rejected')),
 source_module text, source_reference text, created_by uuid references auth.users(id), created_at timestamptz not null default now()
);
create table if not exists unimis.hrc_payroll_salary_change_batches(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 batch_no text not null, change_mode text not null check(change_mode in ('percentage','fixed','grade_step','manual')),
 value numeric(14,4), effective_date date not null, reason text, status text not null default 'draft' check(status in ('draft','approved','applied','cancelled')),
 created_by uuid references auth.users(id), approved_by uuid references auth.users(id), created_at timestamptz not null default now(), unique(tenant_id,batch_no)
);
create table if not exists unimis.hrc_payroll_salary_change_items(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 batch_id uuid not null references unimis.hrc_payroll_salary_change_batches(id) on delete cascade, employee_id uuid not null references unimis.hrc_hr_employees(id) on delete cascade,
 old_salary numeric(14,2) not null, new_salary numeric(14,2) not null, unique(batch_id,employee_id)
);

-- RLS
alter table unimis.hrc_payroll_tax_bands enable row level security; alter table unimis.hrc_payroll_pension_rules enable row level security;
alter table unimis.hrc_payroll_relief_types enable row level security; alter table unimis.hrc_payroll_employee_reliefs enable row level security;
alter table unimis.hrc_payroll_adjustments enable row level security; alter table unimis.hrc_payroll_salary_change_batches enable row level security; alter table unimis.hrc_payroll_salary_change_items enable row level security;
do $$ declare t text; begin
 foreach t in array array['hrc_payroll_tax_bands','hrc_payroll_pension_rules','hrc_payroll_relief_types'] loop
  execute format('create policy %I on unimis.%I for select to authenticated using (tenant_id is null or unimis.is_tenant_member(tenant_id))',t||'_read_007',t);
  execute format('create policy %I on unimis.%I for all to authenticated using (tenant_id is not null and unimis.has_tenant_role(tenant_id,array[''owner'',''administrator'',''payroll_manager''])) with check (tenant_id is not null and unimis.has_tenant_role(tenant_id,array[''owner'',''administrator'',''payroll_manager'']))',t||'_manage_007',t);
 end loop;
 foreach t in array array['hrc_payroll_employee_reliefs','hrc_payroll_adjustments','hrc_payroll_salary_change_batches','hrc_payroll_salary_change_items'] loop
  execute format('create policy %I on unimis.%I for select to authenticated using (unimis.is_tenant_member(tenant_id))',t||'_read_007',t);
  execute format('create policy %I on unimis.%I for all to authenticated using (unimis.has_tenant_role(tenant_id,array[''owner'',''administrator'',''payroll_manager'',''payroll_officer''])) with check (unimis.has_tenant_role(tenant_id,array[''owner'',''administrator'',''payroll_manager'',''payroll_officer'']))',t||'_manage_007',t);
 end loop;
end $$;

-- Official Ghana defaults are global templates (tenant_id NULL); hrc_tenants may clone/override later.
insert into unimis.hrc_payroll_tax_bands(tenant_id,country_code,tax_year,frequency,band_order,band_amount,rate,effective_from,source_note) values
(null,'GH',2026,'monthly',1,588,0,'2026-09-01','GRA Act 1178 / PAYE 2026'),
(null,'GH',2026,'monthly',2,80,5,'2026-09-01','GRA Act 1178 / PAYE 2026'),
(null,'GH',2026,'monthly',3,100,10,'2026-09-01','GRA Act 1178 / PAYE 2026'),
(null,'GH',2026,'monthly',4,2900,17.5,'2026-09-01','GRA Act 1178 / PAYE 2026'),
(null,'GH',2026,'monthly',5,16000,25,'2026-09-01','GRA Act 1178 / PAYE 2026'),
(null,'GH',2026,'monthly',6,30332,30,'2026-09-01','GRA Act 1178 / PAYE 2026'),
(null,'GH',2026,'monthly',7,null,35,'2026-09-01','GRA Act 1178 / PAYE 2026')
on conflict do nothing;
insert into unimis.hrc_payroll_pension_rules(tenant_id,country_code,name,effective_from,employee_rate,employer_rate,tier1_total_rate,tier2_total_rate,minimum_insurable,maximum_insurable,provident_tax_relief_cap_rate,source_note)
values(null,'GH','Ghana 3-Tier Pension 2026','2026-01-01',5.5,13,13.5,5,587.80,69000,16.5,'SSNIT/NPRA 2026') on conflict do nothing;
insert into unimis.hrc_payroll_relief_types(tenant_id,country_code,code,name,calculation_type,annual_amount,percent_rate,max_units,source_note) values
(null,'GH','MARRIAGE','Marriage / Responsibility','fixed_annual',1200,null,1,'GRA personal tax relief'),
(null,'GH','CHILD_EDU','Child Education','per_unit_annual',600,null,3,'GRA personal tax relief'),
(null,'GH','DISABILITY','Disability','percent_income',null,25,1,'GRA personal tax relief'),
(null,'GH','OLD_AGE','Old Age (60+)','fixed_annual',1500,null,1,'GRA personal tax relief'),
(null,'GH','AGED_DEP','Aged Dependent Relative','per_unit_annual',1000,null,2,'GRA personal tax relief'),
(null,'GH','EDUCATION','Professional / Technical Education','fixed_annual',2000,null,1,'GRA personal tax relief'),
(null,'GH','MORTGAGE','Qualifying Mortgage Interest','approved_amount',null,null,1,'GRA personal tax relief') on conflict do nothing;

create or replace function unimis.payroll_progressive_tax(p_tenant uuid,p_country text,p_date date,p_chargeable numeric)
returns numeric language plpgsql stable security definer set search_path=unimis as $$
declare rem numeric:=greatest(coalesce(p_chargeable,0),0); ans numeric:=0; b record; use_amt numeric;
begin
 for b in select * from unimis.hrc_payroll_tax_bands where country_code=p_country and active and effective_from<=p_date and (effective_to is null or effective_to>=p_date) and (tenant_id=p_tenant or tenant_id is null)
          order by (tenant_id is not null) desc, effective_from desc, band_order loop
  -- prefer one effective rule set; avoid mixing global and tenant overrides with same band order
  if exists(select 1 from unimis.hrc_payroll_tax_bands x where x.tenant_id=p_tenant and x.country_code=p_country and x.active and x.effective_from<=p_date and (x.effective_to is null or x.effective_to>=p_date)) and b.tenant_id is null then continue; end if;
  exit when rem<=0; use_amt:=case when b.band_amount is null then rem else least(rem,b.band_amount) end;
  ans:=ans+(use_amt*b.rate/100); rem:=rem-use_amt;
 end loop;
 return round(ans,2);
end $$;
grant execute on function unimis.payroll_progressive_tax(uuid,text,date,numeric) to authenticated;

create or replace function unimis.payroll_create_salary_batch(p_tenant uuid,p_mode text,p_value numeric,p_effective date,p_reason text default null)
returns uuid language plpgsql security definer set search_path=unimis as $$
declare b uuid; bn text; r record; oldv numeric; newv numeric;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','payroll_manager','hr_manager']) then raise exception 'Salary change access denied'; end if;
 bn:='SAL-'||to_char(now(),'YYYYMMDDHH24MISS'); insert into unimis.hrc_payroll_salary_change_batches(tenant_id,batch_no,change_mode,value,effective_date,reason,created_by) values(p_tenant,bn,p_mode,p_value,p_effective,p_reason,auth.uid()) returning id into b;
 for r in select e.id from unimis.hrc_hr_employees e where e.tenant_id=p_tenant and e.employment_status='active' loop
  select coalesce((select sh.new_salary from unimis.hrc_hr_salary_history sh where sh.employee_id=r.id and sh.effective_from<=p_effective order by sh.effective_from desc,sh.created_at desc limit 1),(select c.basic_salary from unimis.hrc_hr_employment_contracts c where c.employee_id=r.id and c.status='active' order by c.start_date desc limit 1),0) into oldv;
  newv:=case when p_mode='percentage' then round(oldv*(1+p_value/100),2) when p_mode='fixed' then round(oldv+p_value,2) else oldv end;
  insert into unimis.hrc_payroll_salary_change_items(tenant_id,batch_id,employee_id,old_salary,new_salary) values(p_tenant,b,r.id,oldv,newv);
 end loop; return b;
end $$;
grant execute on function unimis.payroll_create_salary_batch(uuid,text,numeric,date,text) to authenticated;

create or replace function unimis.payroll_apply_salary_batch(p_tenant uuid,p_batch uuid)
returns void language plpgsql security definer set search_path=unimis as $$
declare r record; d date; rs text;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','payroll_manager']) then raise exception 'Salary approval access denied'; end if;
 select effective_date,reason into d,rs from unimis.hrc_payroll_salary_change_batches where id=p_batch and tenant_id=p_tenant and status='draft'; if d is null then raise exception 'Draft batch not found'; end if;
 for r in select * from unimis.hrc_payroll_salary_change_items where batch_id=p_batch loop
  insert into unimis.hrc_hr_salary_history(tenant_id,employee_id,old_salary,new_salary,change_type,reason,effective_from,approved_by,created_by) values(p_tenant,r.employee_id,r.old_salary,r.new_salary,'bulk_adjustment',rs,d,auth.uid(),auth.uid());
  if d<=current_date then update unimis.hrc_hr_employment_contracts set basic_salary=r.new_salary where tenant_id=p_tenant and employee_id=r.employee_id and status='active'; end if;
 end loop;
 update unimis.hrc_payroll_salary_change_batches set status='applied',approved_by=auth.uid() where id=p_batch;
end $$;
grant execute on function unimis.payroll_apply_salary_batch(uuid,uuid) to authenticated;

-- Replace calculation engine: effective salary + configurable earnings/deductions + Ghana pension/PAYE + approved reliefs/adjustments.
create or replace function unimis.payroll_calculate_run(p_tenant uuid,p_period uuid)
returns uuid language plpgsql security definer set search_path=unimis as $$
declare r uuid; rn text; rec record; re uuid; pend date; country text; pr unimis.hrc_payroll_pension_rules%rowtype;
 basic numeric; earn numeric; ded numeric; taxable_extra numeric; pretax numeric; gross numeric; taxable numeric; insurable numeric; emp_pen numeric; er_pen numeric; tier1 numeric; tier2 numeric;
 pf_emp numeric; pf_er numeric; relief numeric; chargeable numeric; tx numeric; net numeric; adjearn numeric; adjded numeric; adjpretax numeric;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','payroll_manager','payroll_officer']) then raise exception 'Payroll access denied'; end if;
 select end_date into pend from unimis.hrc_payroll_periods where id=p_period and tenant_id=p_tenant; if pend is null then raise exception 'Invalid payroll period'; end if;
 select coalesce(country_code,'GH') into country from unimis.hrc_payroll_settings where tenant_id=p_tenant; country:=coalesce(country,'GH');
 select * into pr from unimis.hrc_payroll_pension_rules x where x.country_code=country and x.active and x.effective_from<=pend and (x.effective_to is null or x.effective_to>=pend) and (x.tenant_id=p_tenant or x.tenant_id is null) order by (x.tenant_id is not null) desc,x.effective_from desc limit 1;
 if country='GH' and not exists(select 1 from unimis.hrc_payroll_tax_bands b where b.country_code='GH' and b.active and b.effective_from<=pend and (b.effective_to is null or b.effective_to>=pend) and (b.tenant_id=p_tenant or b.tenant_id is null)) then raise exception 'No effective PAYE bands configured for payroll period end %',pend; end if;
 select id into r from unimis.hrc_payroll_runs where tenant_id=p_tenant and period_id=p_period;
 if r is null then rn:='RUN-'||to_char(pend,'YYYYMM')||'-'||lpad((1+(select count(*) from unimis.hrc_payroll_runs where tenant_id=p_tenant))::text,3,'0'); insert into unimis.hrc_payroll_runs(tenant_id,period_id,run_no,status,created_by) values(p_tenant,p_period,rn,'draft',auth.uid()) returning id into r;
 else if exists(select 1 from unimis.hrc_payroll_runs where id=r and status in ('approved','posted')) then raise exception 'Approved/posted payroll cannot be recalculated'; end if; delete from unimis.hrc_payroll_run_employees where run_id=r; end if;
 for rec in select e.*,pp.tax_residency,pp.pension_tier1_enabled,pp.pension_tier2_enabled,pp.provident_fund_enabled,pp.provident_employee_rate,pp.provident_employer_rate from unimis.hrc_hr_employees e join unimis.hrc_payroll_profiles pp on pp.employee_id=e.id and pp.active where e.tenant_id=p_tenant and e.employment_status='active' loop
  select coalesce((select sh.new_salary from unimis.hrc_hr_salary_history sh where sh.employee_id=rec.id and sh.effective_from<=pend order by sh.effective_from desc,sh.created_at desc limit 1),(select c.basic_salary from unimis.hrc_hr_employment_contracts c where c.employee_id=rec.id and c.status='active' order by c.start_date desc limit 1),0) into basic;
  select coalesce(sum(case when pc.component_type='earning' then pec.amount else 0 end),0),coalesce(sum(case when pc.component_type='deduction' then pec.amount else 0 end),0),coalesce(sum(case when pc.component_type='earning' and pc.taxable then pec.amount else 0 end),0),coalesce(sum(case when pc.component_type='deduction' and pc.pre_tax then pec.amount else 0 end),0) into earn,ded,taxable_extra,pretax from unimis.hrc_payroll_employee_components pec join unimis.hrc_payroll_components pc on pc.id=pec.component_id where pec.employee_id=rec.id and pec.tenant_id=p_tenant and pec.effective_from<=pend and (pec.effective_to is null or pec.effective_to>=pend) and pc.code<>'BASIC';
  select coalesce(sum(case when adjustment_type in ('earning','arrears','overtime','bonus') then amount else 0 end),0),coalesce(sum(case when adjustment_type in ('deduction','loan','unpaid_absence') then amount else 0 end),0),coalesce(sum(case when adjustment_type='pre_tax_deduction' then amount else 0 end),0) into adjearn,adjded,adjpretax from unimis.hrc_payroll_adjustments where tenant_id=p_tenant and employee_id=rec.id and period_id=p_period and status='approved';
  gross:=basic+earn+adjearn; taxable:=basic+taxable_extra+adjearn; insurable:=least(greatest(basic,coalesce(pr.minimum_insurable,0)),coalesce(pr.maximum_insurable,basic));
  emp_pen:=case when rec.pension_tier1_enabled then round(insurable*coalesce(pr.employee_rate,0)/100,2) else 0 end; er_pen:=case when rec.pension_tier1_enabled then round(insurable*coalesce(pr.employer_rate,0)/100,2) else 0 end;
  tier1:=case when rec.pension_tier1_enabled then round(insurable*coalesce(pr.tier1_total_rate,0)/100,2) else 0 end; tier2:=case when rec.pension_tier2_enabled then round(insurable*coalesce(pr.tier2_total_rate,0)/100,2) else 0 end;
  pf_emp:=case when rec.provident_fund_enabled then round(basic*coalesce(rec.provident_employee_rate,0)/100,2) else 0 end; pf_er:=case when rec.provident_fund_enabled then round(basic*coalesce(rec.provident_employer_rate,0)/100,2) else 0 end;
  select coalesce(sum(case when rt.calculation_type='percent_income' then taxable*coalesce(rt.percent_rate,0)/100 else coalesce(er.approved_annual_amount,case when rt.calculation_type='per_unit_annual' then rt.annual_amount*least(er.units,coalesce(rt.max_units,er.units)) else rt.annual_amount end,0) end)/12,0) into relief from unimis.hrc_payroll_employee_reliefs er join unimis.hrc_payroll_relief_types rt on rt.id=er.relief_type_id where er.tenant_id=p_tenant and er.employee_id=rec.id and er.approved and er.tax_year=extract(year from pend)::int and er.effective_from<=pend and (er.effective_to is null or er.effective_to>=pend);
  chargeable:=greatest(taxable-emp_pen-least(pf_emp+pf_er,basic*coalesce(pr.provident_tax_relief_cap_rate,0)/100)-pretax-adjpretax-relief,0);
  tx:=case when rec.tax_residency='non_resident' then round(chargeable*25/100,2) else unimis.payroll_progressive_tax(p_tenant,country,pend,chargeable) end;
  net:=gross-emp_pen-pf_emp-tx-ded-adjded-pretax-adjpretax;
  insert into unimis.hrc_payroll_run_employees(tenant_id,run_id,employee_id,employee_no,employee_name,basic_salary,other_earnings,gross_pay,employee_pension,employer_pension,tax,other_deductions,net_pay,taxable_income,chargeable_income,tier1_total,tier2_total,provident_employee,provident_employer,tax_relief,employer_cost) values(p_tenant,r,rec.id,rec.employee_no,concat_ws(' ',rec.first_name,rec.other_names,rec.last_name),basic,earn+adjearn,gross,emp_pen,er_pen,tx,ded+adjded+pretax+adjpretax,net,taxable,chargeable,tier1,tier2,pf_emp,pf_er,relief,gross+er_pen+pf_er) returning id into re;
  insert into unimis.hrc_payroll_run_items(tenant_id,run_employee_id,component_code,component_name,component_type,amount,taxable,pensionable) values(p_tenant,re,'BASIC','Basic Salary','earning',basic,true,true),(p_tenant,re,'SSNIT-EE','Employee SSNIT','deduction',emp_pen,false,false),(p_tenant,re,'PAYE','PAYE','deduction',tx,false,false);
  if pf_emp>0 then insert into unimis.hrc_payroll_run_items(tenant_id,run_employee_id,component_code,component_name,component_type,amount,taxable,pensionable) values(p_tenant,re,'TIER3-EE','Provident Fund Employee','deduction',pf_emp,false,false); end if;
 end loop;
 update unimis.hrc_payroll_runs prun set status='calculated',employee_count=x.cnt,gross_total=x.gross,deduction_total=x.ded,employee_pension_total=x.ep,employer_pension_total=x.erp,tax_total=x.tax,net_total=x.net from (select count(*) cnt,coalesce(sum(gross_pay),0) gross,coalesce(sum(other_deductions),0) ded,coalesce(sum(employee_pension),0) ep,coalesce(sum(employer_pension),0) erp,coalesce(sum(tax),0) tax,coalesce(sum(net_pay),0) net from unimis.hrc_payroll_run_employees where run_id=r)x where prun.id=r;
 update unimis.hrc_payroll_periods set status='review' where id=p_period; return r;
end $$;
grant execute on function unimis.payroll_calculate_run(uuid,uuid) to authenticated;

update unimis.hrc_payroll_settings set paye_enabled=true,employee_pension_rate=5.5,employer_pension_rate=13,statutory_note='Ghana statutory templates installed. Effective-dated rules apply; verify future amendments before production.' where country_code='GH';


-- SOURCE 202610160024_payroll_settings_inputs_governance_reports.sql
-- HRPayrollCore 007a: unified settings, employee payroll inputs, separate HR/payroll governance, report builder support

create table if not exists unimis.hrc_payroll_deduction_definitions(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 code text not null, name text not null, description text, employee_or_employer text not null default 'employee' check(employee_or_employer in ('employee','employer','both')),
 calculation_method text not null default 'fixed' check(calculation_method in ('fixed','percentage')), default_value numeric(14,4) not null default 0,
 percentage_base text not null default 'basic', pre_tax boolean not null default false, recurring boolean not null default true,
 mandatory boolean not null default false, requires_consent boolean not null default true, requires_approval boolean not null default true,
 minimum_amount numeric(14,2), maximum_amount numeric(14,2), gl_account text, effective_from date not null default current_date, effective_to date,
 active boolean not null default true, created_at timestamptz not null default now(), unique(tenant_id,code)
);
create table if not exists unimis.hrc_payroll_employee_deductions(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hrc_hr_employees(id) on delete cascade, deduction_id uuid not null references unimis.hrc_payroll_deduction_definitions(id),
 amount numeric(14,2), rate numeric(8,4), effective_from date not null, effective_to date, consent_reference text,
 status text not null default 'pending' check(status in ('draft','pending','approved','rejected','inactive')), created_at timestamptz not null default now()
);
create table if not exists unimis.hrc_payroll_employee_loans(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade, employee_id uuid not null references unimis.hrc_hr_employees(id) on delete cascade,
 loan_type text not null default 'staff_loan', reference text, principal numeric(14,2) not null, installment numeric(14,2) not null, balance numeric(14,2) not null,
 start_period date not null, end_period date, status text not null default 'active' check(status in ('pending','active','settled','suspended','cancelled')), notes text, created_at timestamptz not null default now()
);
create table if not exists unimis.hrc_hrpay_approval_events(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade, domain text not null check(domain in ('hr','payroll')),
 workflow_type text not null, reference text, status text not null default 'pending', submitted_by uuid references auth.users(id), approved_by uuid references auth.users(id),
 submitted_label text, approved_label text, notes text, created_at timestamptz not null default now(), decided_at timestamptz
);
create table if not exists unimis.hrc_hrpay_audit_events(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade, domain text not null check(domain in ('hr','payroll')),
 action text not null, entity_type text not null, entity_id uuid, entity_reference text, old_data jsonb, new_data jsonb, actor_id uuid references auth.users(id), actor_label text,
 created_at timestamptz not null default now()
);

alter table unimis.hrc_payroll_deduction_definitions enable row level security; alter table unimis.hrc_payroll_employee_deductions enable row level security; alter table unimis.hrc_payroll_employee_loans enable row level security; alter table unimis.hrc_hrpay_approval_events enable row level security; alter table unimis.hrc_hrpay_audit_events enable row level security;
do $$ declare t text; begin foreach t in array array['hrc_payroll_deduction_definitions','hrc_payroll_employee_deductions','hrc_payroll_employee_loans','hrc_hrpay_approval_events','hrc_hrpay_audit_events'] loop execute format('create policy %I on unimis.%I for select to authenticated using (unimis.is_tenant_member(tenant_id))',t||'_read_007a',t); execute format('create policy %I on unimis.%I for all to authenticated using (unimis.has_tenant_role(tenant_id,array[''owner'',''administrator'',''payroll_manager'',''payroll_officer''])) with check (unimis.has_tenant_role(tenant_id,array[''owner'',''administrator'',''payroll_manager'',''payroll_officer'']))',t||'_manage_007a',t); end loop; end $$;

-- Seed organization-specific non-statutory deductions for demonstration only; values remain editable.
insert into unimis.hrc_payroll_deduction_definitions(tenant_id,code,name,description,calculation_method,default_value,employee_or_employer,requires_consent,requires_approval,effective_from)
select t.id,'WELFARE','Staff Welfare','Agreed staff welfare contribution','fixed',50,'employee',true,true,'2026-10-01' from unimis.hrc_tenants t where not exists(select 1 from unimis.hrc_payroll_deduction_definitions d where d.tenant_id=t.id and d.code='WELFARE');
insert into unimis.hrc_payroll_deduction_definitions(tenant_id,code,name,description,calculation_method,default_value,employee_or_employer,requires_consent,requires_approval,effective_from)
select t.id,'STAFF_ASSOC','Staff Association','Agreed staff association contribution','fixed',25,'employee',true,true,'2026-10-01' from unimis.hrc_tenants t where not exists(select 1 from unimis.hrc_payroll_deduction_definitions d where d.tenant_id=t.id and d.code='STAFF_ASSOC');

-- Demonstration payroll inputs: pending so payroll approval is visible before calculation.
insert into unimis.hrc_payroll_adjustments(tenant_id,employee_id,period_id,adjustment_type,code,description,amount,taxable,pensionable,status,source_module,source_reference)
select e.tenant_id,e.id,p.id,'overtime','OT-DEMO','Approved HR overtime imported for payroll',180,true,false,'pending','attendance','DEMO-OT-001'
from unimis.hrc_hr_employees e join lateral(select id from unimis.hrc_payroll_periods p where p.tenant_id=e.tenant_id order by start_date desc limit 1)p on true
where e.employment_status='active' and e.employee_no=(select min(e2.employee_no) from unimis.hrc_hr_employees e2 where e2.tenant_id=e.tenant_id and e2.employment_status='active')
and not exists(select 1 from unimis.hrc_payroll_adjustments a where a.tenant_id=e.tenant_id and a.source_reference='DEMO-OT-001');

-- Separate governance seed demonstrates the two approval/audit streams.
insert into unimis.hrc_hrpay_approval_events(tenant_id,domain,workflow_type,reference,status,submitted_label,notes)
select id,'hr','attendance_correction','ATT-DEMO-001','pending','HR Officer','Example HR approval stream' from unimis.hrc_tenants t where not exists(select 1 from unimis.hrc_hrpay_approval_events a where a.tenant_id=t.id and a.reference='ATT-DEMO-001');
insert into unimis.hrc_hrpay_approval_events(tenant_id,domain,workflow_type,reference,status,submitted_label,notes)
select id,'payroll','payroll_input','PAY-DEMO-001','pending','Payroll Officer','Example payroll approval stream' from unimis.hrc_tenants t where not exists(select 1 from unimis.hrc_hrpay_approval_events a where a.tenant_id=t.id and a.reference='PAY-DEMO-001');
insert into unimis.hrc_hrpay_audit_events(tenant_id,domain,action,entity_type,entity_reference,actor_label,new_data)
select id,'payroll','settings_seeded','hrc_payroll_settings','007A','System',jsonb_build_object('package','007a','note','Configurable payroll settings enabled') from unimis.hrc_tenants t where not exists(select 1 from unimis.hrc_hrpay_audit_events a where a.tenant_id=t.id and a.entity_reference='007A');

-- Make tenant PAYE copies safely override global templates. Global templates remain immutable historical references.
create or replace function unimis.payroll_progressive_tax(p_tenant uuid,p_country text,p_date date,p_chargeable numeric)
returns numeric language plpgsql stable security definer set search_path=unimis as $$
declare rem numeric:=greatest(coalesce(p_chargeable,0),0); total numeric:=0; b record; take_amt numeric;
begin
 for b in select * from unimis.hrc_payroll_tax_bands x where x.country_code=p_country and x.frequency='monthly' and x.active and x.effective_from<=p_date and (x.effective_to is null or x.effective_to>=p_date) and (x.tenant_id=p_tenant or x.tenant_id is null) order by (x.tenant_id is not null) desc,x.effective_from desc,x.band_order loop
  -- If tenant-specific bands exist for the effective date, ignore global bands.
  if b.tenant_id is null and exists(select 1 from unimis.hrc_payroll_tax_bands z where z.tenant_id=p_tenant and z.country_code=p_country and z.frequency='monthly' and z.active and z.effective_from<=p_date and (z.effective_to is null or z.effective_to>=p_date)) then continue; end if;
  exit when rem<=0; take_amt:=case when b.band_amount is null then rem else least(rem,b.band_amount) end; total:=total+(take_amt*b.rate/100); rem:=rem-take_amt;
 end loop; return round(total,2);
end $$;

grant execute on function unimis.payroll_progressive_tax(uuid,text,date,numeric) to authenticated;




-- Refresh Supabase/PostgREST schema cache after this stage.
NOTIFY pgrst, 'reload schema';
