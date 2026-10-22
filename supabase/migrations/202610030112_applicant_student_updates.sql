begin;

create table if not exists public.institution_student_id_counters(
 institution_id uuid not null references public.institutions(id) on delete cascade,
 scope_key text not null,admission_year integer not null,last_number bigint not null default 0,
 primary key(institution_id,scope_key,admission_year)
);
alter table public.institution_student_id_counters enable row level security;

create or replace function public.generate_student_number()
returns trigger language plpgsql security definer set search_path='' as $$
declare cfg jsonb; fmt text; pref text; digits integer; scope text; prog uuid; dept uuid; pc text; dc text; fc text; yr integer; seq bigint; candidate text; key text;
begin
 if nullif(btrim(new.student_number),'') is not null then return new; end if;
 select academic_settings->'student_numbering' into cfg from public.institution_settings where institution_id=new.institution_id;
 fmt:=coalesce(nullif(cfg->>'format',''),'{FACULTY}/{DEPARTMENT}/{YY}/{SEQ}');
 pref:=coalesce(cfg->>'prefix','');digits:=coalesce((cfg->>'digits')::integer,3);scope:=coalesce(cfg->>'scope','department');
 if digits not between 1 and 12 or position('{SEQ}' in fmt)=0 or length(fmt)>100 or
  regexp_replace(fmt,'\{(PREFIX|FACULTY|DEPARTMENT|PROGRAMME|YY|YYYY|SEQ)\}','','g') ~ '[{}]' then raise exception 'Invalid student ID format or sequence length'; end if;
 select o.programme_id into prog from public.admission_offers o where o.application_id=new.application_id and o.institution_id=new.institution_id and o.response_status='accepted' order by coalesce(o.responded_at,o.created_at) desc limit 1;
 select d.id,p.code,d.code,f.code into dept,pc,dc,fc from public.programmes p left join public.departments d on d.id=p.department_id left join public.faculties f on f.id=d.faculty_id where p.id=prog and p.institution_id=new.institution_id;
 if (position('{FACULTY}' in fmt)>0 and nullif(fc,'') is null) or (position('{DEPARTMENT}' in fmt)>0 and nullif(dc,'') is null) or (position('{PROGRAMME}' in fmt)>0 and nullif(pc,'') is null) then raise exception 'Selected student ID format requires configured academic codes'; end if;
 yr:=extract(year from coalesce(new.admission_date,current_date))::integer;
 key:=case when scope='institution' then 'institution' when scope='programme' then 'programme:'||coalesce(prog::text,'unassigned') else 'department:'||coalesce(dept::text,'unassigned') end;
 if position('{YY}' in fmt)=0 and position('{YYYY}' in fmt)=0 then yr:=0; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.institution_id::text,0));
 loop
  insert into public.institution_student_id_counters(institution_id,scope_key,admission_year,last_number) values(new.institution_id,key,yr,1)
  on conflict(institution_id,scope_key,admission_year) do update set last_number=public.institution_student_id_counters.last_number+1 returning last_number into seq;
  candidate:=replace(replace(replace(replace(replace(replace(replace(fmt,'{PREFIX}',pref),'{FACULTY}',coalesce(fc,'')),'{DEPARTMENT}',coalesce(dc,'')),'{PROGRAMME}',coalesce(pc,'')),'{YY}',right(extract(year from coalesce(new.admission_date,current_date))::integer::text,2)),'{YYYY}',extract(year from coalesce(new.admission_date,current_date))::integer::text),'{SEQ}',lpad(seq::text,greatest(digits,length(seq::text)),'0'));
  exit when not exists(select 1 from public.students where institution_id=new.institution_id and student_number=candidate);
 end loop;
 new.student_number:=candidate;return new;
end $$;

-- Guard storage paths before casting and enforce ownership and edit locks.
create or replace function public.unimis_admission_document_access(p_path text,p_write boolean default false)
returns boolean language plpgsql stable security definer set search_path='' as $$
declare app public.applications%rowtype; own boolean;
begin
 if split_part(p_path,'/',1)!~*'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' or split_part(p_path,'/',2)!~*'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return false; end if;
 select * into app from public.applications where id=split_part(p_path,'/',2)::uuid and institution_id=split_part(p_path,'/',1)::uuid;
 if not found then return false; end if;
 select exists(select 1 from public.applicants where id=app.applicant_id and user_id=auth.uid()) into own;
 if p_write then return own and lower(app.status) in ('draft','incomplete','returned') and lower(coalesce(app.payment_status,'')) not in ('paid','verified'); end if;
 return own or public.has_permission(app.institution_id,'admissions.view') or public.has_permission(app.institution_id,'students.view') or public.has_permission(app.institution_id,'students.manage');
end $$;
revoke all on function public.unimis_admission_document_access(text,boolean) from public;
grant execute on function public.unimis_admission_document_access(text,boolean) to authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('admission-documents','admission-documents',false,10485760,array['application/pdf','image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=10485760,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists "Applicants can upload own admission documents" on storage.objects;
drop policy if exists "Applicants can read own admission documents" on storage.objects;
drop policy if exists "Applicants can delete own admission documents" on storage.objects;
drop policy if exists "Applicants delete own admission documents" on storage.objects;
drop policy if exists applicant_documents_insert112 on storage.objects;
drop policy if exists applicant_documents_read112 on storage.objects;
drop policy if exists applicant_documents_delete112 on storage.objects;
create policy applicant_documents_insert112 on storage.objects for insert to authenticated with check(bucket_id='admission-documents' and public.unimis_admission_document_access(name,true));
create policy applicant_documents_read112 on storage.objects for select to authenticated using(bucket_id='admission-documents' and public.unimis_admission_document_access(name,false));
create policy applicant_documents_delete112 on storage.objects for delete to authenticated using(bucket_id='admission-documents' and public.unimis_admission_document_access(name,true));

create or replace function public.unimis_applicant_save_document(p_application_id uuid,p_document_type text,p_file_name text,p_storage_path text,p_mime_type text,p_file_size_bytes bigint,p_replace_document_id uuid default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare app public.applications%rowtype; result uuid;
begin
 select * into app from public.applications where id=p_application_id for update;
 if not found or not public.unimis_admission_document_access(p_storage_path,true) or split_part(p_storage_path,'/',2)<>p_application_id::text then raise exception 'Upload is not authorised, or this application is locked'; end if;
 if p_mime_type is null or p_mime_type not in ('application/pdf','image/jpeg','image/png','image/webp') or p_file_size_bytes is null or p_file_size_bytes<=0 or p_file_size_bytes>10485760 then raise exception 'Choose a PDF, JPG, PNG or WebP file up to 10 MB'; end if;
 if not exists(select 1 from storage.objects where bucket_id='admission-documents' and name=p_storage_path) then raise exception 'Upload did not complete. Please retry'; end if;
 if nullif(btrim(p_document_type),'') is null then raise exception 'Document type is required'; end if;
 if p_replace_document_id is null then
  insert into public.application_documents(institution_id,application_id,document_type,file_name,storage_path,mime_type,file_size_bytes,verification_status) values(app.institution_id,app.id,btrim(p_document_type),p_file_name,p_storage_path,p_mime_type,p_file_size_bytes,'pending') returning id into result;
 else
  update public.application_documents set file_name=p_file_name,storage_path=p_storage_path,mime_type=p_mime_type,file_size_bytes=p_file_size_bytes,verification_status='pending' where id=p_replace_document_id and application_id=app.id and institution_id=app.institution_id and document_type=p_document_type returning id into result;
  if result is null then raise exception 'Original document not found'; end if;
 end if;
 return result;
end $$;
revoke all on function public.unimis_applicant_save_document(uuid,text,text,text,text,bigint,uuid) from public;
grant execute on function public.unimis_applicant_save_document(uuid,text,text,text,text,bigint,uuid) to authenticated;

create or replace function public.unimis_student_search_profile(p_student_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare inst uuid; result jsonb; photo text;
begin
 select institution_id into inst from public.students where id=p_student_id;
 if inst is null or not (public.has_permission(inst,'students.view') or public.has_permission(inst,'students.manage')) then raise exception 'Student record access required'; end if;
 result:=public.unimis_student_profile(p_student_id);
 select d.storage_path into photo from public.application_documents d join public.students s on s.application_id=d.application_id where s.id=p_student_id and d.institution_id=inst and (lower(d.document_type) like '%photo%' or lower(d.document_type) like '%passport%') and coalesce(d.mime_type,'') like 'image/%' order by d.created_at desc limit 1;
 return result||jsonb_build_object('institution',(select jsonb_build_object('name',i.name) from public.institutions i where i.id=inst),'applicant_photo_path',photo,'gpa_history',coalesce((select jsonb_agg(to_jsonb(x) order by x.start_date desc,x.period_number desc) from (
 select spr.gpa,spr.cgpa,spr.attempted_credits,spr.earned_credits,spr.total_quality_points,ap.name academic_period,ay.name academic_year,ap.start_date,ap.period_number
 from public.student_period_results spr join public.academic_periods ap on ap.id=spr.academic_period_id join public.academic_years ay on ay.id=ap.academic_year_id
 where spr.student_id=p_student_id and spr.institution_id=inst and spr.status='published'
 )x),'[]'::jsonb));
end $$;
revoke all on function public.unimis_student_search_profile(uuid) from public;
grant execute on function public.unimis_student_search_profile(uuid) to authenticated;
commit;
notify pgrst,'reload schema';
