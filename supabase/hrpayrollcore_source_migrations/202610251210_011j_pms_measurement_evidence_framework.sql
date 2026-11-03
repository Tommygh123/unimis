-- 011j: evidence-led PMS measurement framework.
alter table public.hr_performance_metric_library
 add column if not exists measurement_type text not null default 'numeric',
 add column if not exists data_source text not null default 'manager_verified',
 add column if not exists measurement_method text,
 add column if not exists evidence_required boolean not null default true,
 add column if not exists evidence_min_count integer not null default 1,
 add column if not exists rubric jsonb not null default '[]'::jsonb,
 add column if not exists checklist jsonb not null default '[]'::jsonb;

do $$ begin
 if not exists(select 1 from pg_constraint where conname='hr_perf_metric_measurement_type_check') then
  alter table public.hr_performance_metric_library add constraint hr_perf_metric_measurement_type_check check(measurement_type in ('system_calculated','formula','numeric','milestone','behavioral_rubric','compliance_checklist','development'));
 end if;
end $$;

create table if not exists public.hr_performance_evidence_attachments(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 review_id uuid not null references public.hr_performance_reviews(id) on delete cascade,
 plan_item_id uuid references public.hr_performance_plan_items(id) on delete cascade,
 checkin_id uuid references public.hr_performance_checkins(id) on delete cascade,
 file_name text not null, storage_path text not null, mime_type text, file_size bigint,
 description text, verification_status text not null default 'pending' check(verification_status in ('pending','verified','rejected')),
 verified_by uuid, verified_at timestamptz, uploaded_by uuid default auth.uid(), created_at timestamptz not null default now()
);
alter table public.hr_performance_evidence_attachments enable row level security;
drop policy if exists tenant_member_all on public.hr_performance_evidence_attachments;
create policy tenant_member_all on public.hr_performance_evidence_attachments for all using(public.is_tenant_member(tenant_id)) with check(public.is_tenant_member(tenant_id));

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('performance-evidence','performance-evidence',false,10485760,array['image/jpeg','image/png','image/webp','application/pdf','text/plain','text/csv','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','application/vnd.openxmlformats-officedocument.wordprocessingml.document'])
on conflict(id) do update set file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists performance_evidence_member_insert on storage.objects;
create policy performance_evidence_member_insert on storage.objects for insert to authenticated with check(bucket_id='performance-evidence' and public.is_tenant_member((storage.foldername(name))[1]::uuid));
drop policy if exists performance_evidence_member_select on storage.objects;
create policy performance_evidence_member_select on storage.objects for select to authenticated using(bucket_id='performance-evidence' and public.is_tenant_member((storage.foldername(name))[1]::uuid));
drop policy if exists performance_evidence_member_delete on storage.objects;
create policy performance_evidence_member_delete on storage.objects for delete to authenticated using(bucket_id='performance-evidence' and public.is_tenant_member((storage.foldername(name))[1]::uuid));

-- System attendance result: percentage of attendance records that are present/late/half-day/on approved leave.
create or replace function public.hr_performance_attendance_result(p_tenant uuid,p_employee uuid,p_start date,p_end date) returns numeric
language plpgsql security definer set search_path=public as $$
declare total_count integer; acceptable integer;
begin
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select count(*),count(*) filter(where status in ('present','late','half_day','on_leave','holiday','off_day')) into total_count,acceptable
 from public.hr_attendance_records where tenant_id=p_tenant and employee_id=p_employee and work_date between p_start and p_end;
 if total_count=0 then return null; end if;
 return round(acceptable::numeric*100/total_count,2);
end $$;
grant execute on function public.hr_performance_attendance_result(uuid,uuid,date,date) to authenticated;

-- Mark the standard attendance KPI as system-calculated where it exists.
update public.hr_performance_metric_library set measurement_type='system_calculated',data_source='attendance_module',measurement_method='Calculated from HRPayrollCore attendance records for the selected review period.',evidence_required=false,evidence_min_count=0
where lower(name) like '%attendance%punctuality%';
update public.hr_performance_metric_library set measurement_type='behavioral_rubric',data_source='manager_verified',unit='score',measurement_method='Select the behaviourally anchored statement best supported by documented observations/evidence.',rubric='[{"score":1,"label":"Unsatisfactory","anchor":"Serious or persistent breaches of expected professional or ethical standards."},{"score":2,"label":"Needs improvement","anchor":"Repeated concerns requiring management intervention or coaching."},{"score":3,"label":"Meets expectations","anchor":"Generally professional, ethical and compliant; minor issues are corrected promptly."},{"score":4,"label":"Exceeds expectations","anchor":"Consistently professional, ethical and dependable with little or no corrective intervention."},{"score":5,"label":"Exceptional","anchor":"Consistently models integrity and professional conduct and positively influences others."}]'::jsonb,evidence_required=true,evidence_min_count=1
where lower(name) like '%professional conduct%ethic%';
