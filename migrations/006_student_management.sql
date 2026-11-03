-- ============================================================
-- UNIMIS MODULE 04
-- STUDENT MANAGEMENT
-- 006_student_management.sql
-- ============================================================

create table if not exists public.students (
 id uuid primary key default gen_random_uuid(),
 institution_id uuid not null references public.institutions(id) on delete cascade,
 user_id uuid references auth.users(id) on delete set null,
 applicant_id uuid references public.applicants(id) on delete set null,
 application_id uuid references public.applications(id) on delete set null,
 student_number text not null,
 first_name text not null, middle_name text, last_name text not null,
 date_of_birth date,
 gender text check (gender in ('male','female','other','prefer_not_to_say')),
 email text, phone text, nationality text default 'Ghanaian',
 address text, city text, region text, admission_date date,
 student_type text not null default 'regular'
   check (student_type in ('regular','mature','transfer','international','exchange','other')),
 status text not null default 'active'
   check (status in ('applicant','admitted','active','deferred','suspended','withdrawn','completed','graduated','dismissed','inactive')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(institution_id,student_number),
 unique(institution_id,user_id),
 unique(institution_id,application_id)
);

create table if not exists public.student_programme_enrolments (
 id uuid primary key default gen_random_uuid(),
 institution_id uuid not null references public.institutions(id) on delete cascade,
 student_id uuid not null references public.students(id) on delete cascade,
 programme_id uuid not null references public.programmes(id) on delete restrict,
 admission_academic_year_id uuid references public.academic_years(id) on delete set null,
 cohort_year integer,
 current_level integer not null default 100 check(current_level>0),
 enrolment_status text not null default 'active'
   check(enrolment_status in ('admitted','active','deferred','suspended','withdrawn','completed','graduated','transferred')),
 start_date date, expected_completion_date date, completion_date date,
 is_primary boolean not null default true,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create unique index if not exists uq_primary_student_programme
on public.student_programme_enrolments(student_id)
where is_primary=true and enrolment_status in ('admitted','active','deferred','suspended');

create table if not exists public.student_guardians (
 id uuid primary key default gen_random_uuid(),
 institution_id uuid not null references public.institutions(id) on delete cascade,
 student_id uuid not null references public.students(id) on delete cascade,
 full_name text not null, relationship text, phone text, alternate_phone text,
 email text, address text, occupation text,
 is_primary boolean not null default false,
 is_emergency_contact boolean not null default false,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table if not exists public.student_status_history (
 id uuid primary key default gen_random_uuid(),
 institution_id uuid not null references public.institutions(id) on delete cascade,
 student_id uuid not null references public.students(id) on delete cascade,
 old_status text, new_status text not null, reason text,
 effective_date date not null default current_date,
 changed_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now()
);

create table if not exists public.student_documents (
 id uuid primary key default gen_random_uuid(),
 institution_id uuid not null references public.institutions(id) on delete cascade,
 student_id uuid not null references public.students(id) on delete cascade,
 document_type text not null, file_name text not null, storage_path text not null,
 mime_type text, file_size_bytes bigint check(file_size_bytes is null or file_size_bytes>=0),
 created_at timestamptz not null default now()
);

create sequence if not exists public.student_number_seq start 1001;

create or replace function public.generate_student_number()
returns trigger language plpgsql security definer set search_path=''
as $$
declare inst_code text; yr text; seq_no bigint;
begin
 if new.student_number is null or btrim(new.student_number)='' then
  select coalesce(nullif(i.short_name,''),i.code) into inst_code
  from public.institutions i where i.id=new.institution_id;
  if inst_code is null then raise exception 'Invalid institution'; end if;
  yr:=coalesce(extract(year from new.admission_date)::integer::text,to_char(current_date,'YYYY'));
  seq_no:=nextval('public.student_number_seq');
  new.student_number:=upper(regexp_replace(inst_code,'[^A-Za-z0-9]','','g'))||'-'||yr||'-'||lpad(seq_no::text,6,'0');
 end if;
 return new;
end $$;
revoke all on function public.generate_student_number() from public;
drop trigger if exists trg_generate_student_number on public.students;
create trigger trg_generate_student_number before insert on public.students
for each row execute function public.generate_student_number();

create or replace function public.log_student_status_change()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
 if old.status is distinct from new.status then
  insert into public.student_status_history(institution_id,student_id,old_status,new_status,effective_date,changed_by)
  values(new.institution_id,new.id,old.status,new.status,current_date,auth.uid());
 end if;
 return new;
end $$;
revoke all on function public.log_student_status_change() from public;
drop trigger if exists trg_student_status_history on public.students;
create trigger trg_student_status_history after update of status on public.students
for each row execute function public.log_student_status_change();

create index if not exists idx_students_institution on public.students(institution_id);
create index if not exists idx_students_status on public.students(institution_id,status);
create index if not exists idx_students_user on public.students(user_id);
create index if not exists idx_student_enrolments_student on public.student_programme_enrolments(student_id);
create index if not exists idx_student_enrolments_programme on public.student_programme_enrolments(programme_id);
create index if not exists idx_student_guardians_student on public.student_guardians(student_id);
create index if not exists idx_student_status_history_student on public.student_status_history(student_id);
create index if not exists idx_student_documents_student on public.student_documents(student_id);

do $$ declare t text; begin
 foreach t in array array['students','student_programme_enrolments','student_guardians'] loop
  execute format('drop trigger if exists trg_%I_updated_at on public.%I',t,t);
  execute format('create trigger trg_%I_updated_at before update on public.%I for each row execute function public.set_updated_at()',t,t);
 end loop;
end $$;

alter table public.students enable row level security;
alter table public.student_programme_enrolments enable row level security;
alter table public.student_guardians enable row level security;
alter table public.student_status_history enable row level security;
alter table public.student_documents enable row level security;

do $$ declare t text; begin
 foreach t in array array['students','student_programme_enrolments','student_guardians','student_status_history','student_documents'] loop
  execute format('drop policy if exists "Student viewers can view %s" on public.%I',t,t);
  execute format('create policy "Student viewers can view %s" on public.%I for select to authenticated using (public.has_permission(institution_id,''students.view'') or public.has_permission(institution_id,''students.manage''))',t,t);
  execute format('drop policy if exists "Student managers can manage %s" on public.%I',t,t);
  execute format('create policy "Student managers can manage %s" on public.%I for all to authenticated using (public.has_permission(institution_id,''students.manage'')) with check (public.has_permission(institution_id,''students.manage''))',t,t);
 end loop;
end $$;

drop policy if exists "Students can view own student record" on public.students;
create policy "Students can view own student record" on public.students for select to authenticated
using(user_id=(select auth.uid()));

drop policy if exists "Students can view own programme enrolments" on public.student_programme_enrolments;
create policy "Students can view own programme enrolments" on public.student_programme_enrolments for select to authenticated
using(exists(select 1 from public.students s where s.id=student_id and s.user_id=(select auth.uid())));

drop policy if exists "Students can view own guardians" on public.student_guardians;
create policy "Students can view own guardians" on public.student_guardians for select to authenticated
using(exists(select 1 from public.students s where s.id=student_id and s.user_id=(select auth.uid())));

drop policy if exists "Students can view own status history" on public.student_status_history;
create policy "Students can view own status history" on public.student_status_history for select to authenticated
using(exists(select 1 from public.students s where s.id=student_id and s.user_id=(select auth.uid())));

drop policy if exists "Students can view own documents" on public.student_documents;
create policy "Students can view own documents" on public.student_documents for select to authenticated
using(exists(select 1 from public.students s where s.id=student_id and s.user_id=(select auth.uid())));

select
 (select count(*) from public.students) students,
 (select count(*) from public.student_programme_enrolments) programme_enrolments,
 (select count(*) from public.student_guardians) guardians,
 (select count(*) from public.student_status_history) status_history,
 (select count(*) from public.student_documents) documents;

-- END MODULE 04
