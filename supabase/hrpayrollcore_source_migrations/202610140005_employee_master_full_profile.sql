-- Package 002d: Full HR Employee Master.
alter table public.hr_employees
 add column if not exists gender text,
 add column if not exists marital_status text,
 add column if not exists nationality text default 'Ghanaian',
 add column if not exists national_id text,
 add column if not exists residential_address text,
 add column if not exists postal_address text,
 add column if not exists supervisor_id uuid references public.hr_employees(id) on delete set null;

alter table public.payroll_profiles
 add column if not exists bank_branch text,
 add column if not exists momo_number text,
 add column if not exists momo_network text;

create table if not exists public.hr_employee_qualifications(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 employee_id uuid not null references public.hr_employees(id) on delete cascade,
 qualification_type text not null default 'academic', qualification text not null, institution text,
 field_of_study text, start_year integer, completion_year integer, certificate_no text, notes text,
 created_at timestamptz default now()
);
create table if not exists public.hr_employee_documents(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 employee_id uuid not null references public.hr_employees(id) on delete cascade,
 document_type text not null, title text not null, file_path text not null, issue_date date, expiry_date date,
 notes text, uploaded_by uuid references auth.users(id), created_at timestamptz default now()
);
create table if not exists public.hr_emergency_contacts(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 employee_id uuid not null references public.hr_employees(id) on delete cascade,
 full_name text not null, relationship text, phone text not null, alternate_phone text, address text,
 is_primary boolean default true, created_at timestamptz default now()
);
create table if not exists public.hr_employment_events(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 employee_id uuid not null references public.hr_employees(id) on delete cascade,
 event_type text not null, effective_date date not null, title text, details jsonb default '{}'::jsonb,
 created_by uuid references auth.users(id), created_at timestamptz default now()
);

do $$ declare t text; begin
 foreach t in array array['hr_employee_qualifications','hr_employee_documents','hr_emergency_contacts','hr_employment_events'] loop
   execute format('alter table public.%I enable row level security',t);
   execute format('create policy %I on public.%I for select using(public.is_tenant_member(tenant_id))',t||'_read',t);
   execute format('create policy %I on public.%I for insert with check(public.has_tenant_role(tenant_id,array[''owner'',''administrator'',''hr_manager'',''hr_officer'']))',t||'_insert',t);
   execute format('create policy %I on public.%I for update using(public.has_tenant_role(tenant_id,array[''owner'',''administrator'',''hr_manager'',''hr_officer''])) with check(public.has_tenant_role(tenant_id,array[''owner'',''administrator'',''hr_manager'',''hr_officer'']))',t||'_update',t);
   execute format('create policy %I on public.%I for delete using(public.has_tenant_role(tenant_id,array[''owner'',''administrator'',''hr_manager'']))',t||'_delete',t);
 end loop;
end $$;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('employee-documents','employee-documents',false,10485760,array['application/pdf','image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists employee_documents_read on storage.objects;
create policy employee_documents_read on storage.objects for select to authenticated
using(bucket_id='employee-documents' and public.is_tenant_member(((storage.foldername(name))[1])::uuid));
drop policy if exists employee_documents_insert on storage.objects;
create policy employee_documents_insert on storage.objects for insert to authenticated
with check(bucket_id='employee-documents' and public.has_tenant_role(((storage.foldername(name))[1])::uuid,array['owner','administrator','hr_manager','hr_officer']));
drop policy if exists employee_documents_update on storage.objects;
create policy employee_documents_update on storage.objects for update to authenticated
using(bucket_id='employee-documents' and public.has_tenant_role(((storage.foldername(name))[1])::uuid,array['owner','administrator','hr_manager','hr_officer']))
with check(bucket_id='employee-documents' and public.has_tenant_role(((storage.foldername(name))[1])::uuid,array['owner','administrator','hr_manager','hr_officer']));
drop policy if exists employee_documents_delete on storage.objects;
create policy employee_documents_delete on storage.objects for delete to authenticated
using(bucket_id='employee-documents' and public.has_tenant_role(((storage.foldername(name))[1])::uuid,array['owner','administrator','hr_manager']));

create or replace function public.hr_record_employment_event(p_tenant uuid,p_employee uuid,p_type text,p_effective date,p_title text,p_details jsonb default '{}'::jsonb)
returns uuid language plpgsql security definer set search_path=public as $$ declare x uuid; begin
 if not public.has_tenant_role(p_tenant,array['owner','administrator','hr_manager','hr_officer']) then raise exception 'HR access denied'; end if;
 insert into public.hr_employment_events(tenant_id,employee_id,event_type,effective_date,title,details,created_by)
 values(p_tenant,p_employee,p_type,coalesce(p_effective,current_date),p_title,coalesce(p_details,'{}'::jsonb),auth.uid()) returning id into x;
 return x; end $$;
grant execute on function public.hr_record_employment_event(uuid,uuid,text,date,text,jsonb) to authenticated;

notify pgrst, 'reload schema';
