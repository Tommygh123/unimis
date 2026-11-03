-- ============================================================
-- UniMIS Admissions Phase 2
-- Qualifications + Documents + Application Review
-- ============================================================

grant usage on schema public to authenticated;

grant select, insert, update
on table public.applicant_qualifications
to authenticated;

grant select, insert, update
on table public.application_documents
to authenticated;


-- ------------------------------------------------------------
-- RLS: applicant qualifications
-- ------------------------------------------------------------

alter table public.applicant_qualifications enable row level security;

drop policy if exists "Admissions viewers can view applicant qualifications"
on public.applicant_qualifications;

create policy "Admissions viewers can view applicant qualifications"
on public.applicant_qualifications
for select
to authenticated
using (
  public.has_permission(institution_id, 'admissions.view')
  or public.has_permission(institution_id, 'admissions.manage')
);

drop policy if exists "Admissions managers can manage applicant qualifications"
on public.applicant_qualifications;

create policy "Admissions managers can manage applicant qualifications"
on public.applicant_qualifications
for all
to authenticated
using (
  public.has_permission(institution_id, 'admissions.manage')
)
with check (
  public.has_permission(institution_id, 'admissions.manage')
);


-- ------------------------------------------------------------
-- RLS: application documents
-- ------------------------------------------------------------

alter table public.application_documents enable row level security;

drop policy if exists "Admissions viewers can view application documents"
on public.application_documents;

create policy "Admissions viewers can view application documents"
on public.application_documents
for select
to authenticated
using (
  public.has_permission(institution_id, 'admissions.view')
  or public.has_permission(institution_id, 'admissions.manage')
);

drop policy if exists "Admissions managers can manage application documents"
on public.application_documents;

create policy "Admissions managers can manage application documents"
on public.application_documents
for all
to authenticated
using (
  public.has_permission(institution_id, 'admissions.manage')
)
with check (
  public.has_permission(institution_id, 'admissions.manage')
);


-- ------------------------------------------------------------
-- Standardise document verification statuses for this workflow.
-- Existing default 'pending' remains valid.
-- ------------------------------------------------------------

alter table public.application_documents
drop constraint if exists application_documents_verification_status_check;

alter table public.application_documents
add constraint application_documents_verification_status_check
check (
  verification_status in ('pending', 'verified', 'rejected')
);


-- ------------------------------------------------------------
-- Private storage bucket for admissions files
-- ------------------------------------------------------------

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'admission-documents',
  'admission-documents',
  false,
  10485760,
  array[
    'application/pdf',
    'image/jpeg',
    'image/png',
    'image/webp'
  ]::text[]
)
on conflict (id)
do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;


drop policy if exists "Admissions staff can read admission documents"
on storage.objects;

create policy "Admissions staff can read admission documents"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'admission-documents'
  and public.has_permission(
    ((storage.foldername(name))[1])::uuid,
    'admissions.view'
  )
);


drop policy if exists "Admissions managers can upload admission documents"
on storage.objects;

create policy "Admissions managers can upload admission documents"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'admission-documents'
  and public.has_permission(
    ((storage.foldername(name))[1])::uuid,
    'admissions.manage'
  )
);


drop policy if exists "Admissions managers can update admission documents"
on storage.objects;

create policy "Admissions managers can update admission documents"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'admission-documents'
  and public.has_permission(
    ((storage.foldername(name))[1])::uuid,
    'admissions.manage'
  )
)
with check (
  bucket_id = 'admission-documents'
  and public.has_permission(
    ((storage.foldername(name))[1])::uuid,
    'admissions.manage'
  )
);


drop policy if exists "Admissions managers can delete admission documents"
on storage.objects;

create policy "Admissions managers can delete admission documents"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'admission-documents'
  and public.has_permission(
    ((storage.foldername(name))[1])::uuid,
    'admissions.manage'
  )
);


-- ------------------------------------------------------------
-- Document verification
-- ------------------------------------------------------------

create or replace function public.review_application_document(
  p_document_id uuid,
  p_status text,
  p_notes text default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_institution_id uuid;
begin
  if p_status not in ('pending', 'verified', 'rejected') then
    raise exception 'Invalid document verification status';
  end if;

  select institution_id
  into v_institution_id
  from public.application_documents
  where id = p_document_id;

  if v_institution_id is null then
    raise exception 'Application document not found';
  end if;

  if not public.has_permission(
    v_institution_id,
    'admissions.manage'
  ) then
    raise exception 'You do not have permission to review admission documents';
  end if;

  update public.application_documents
  set
    verification_status = p_status,
    verified_by = case
      when p_status = 'pending' then null
      else auth.uid()
    end,
    verified_at = case
      when p_status = 'pending' then null
      else now()
    end,
    notes = p_notes
  where id = p_document_id;

  return true;
end;
$$;

revoke all
on function public.review_application_document(uuid, text, text)
from public;

grant execute
on function public.review_application_document(uuid, text, text)
to authenticated;


-- ------------------------------------------------------------
-- Complete internal review without inventing an unknown
-- applications.status value. Offer/decision workflow is Phase 3.
-- ------------------------------------------------------------

create or replace function public.complete_internal_application_review(
  p_application_id uuid,
  p_notes text default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_institution_id uuid;
begin
  select institution_id
  into v_institution_id
  from public.applications
  where id = p_application_id;

  if v_institution_id is null then
    raise exception 'Application not found';
  end if;

  if not public.has_permission(
    v_institution_id,
    'admissions.manage'
  ) then
    raise exception 'You do not have permission to review applications';
  end if;

  update public.applications
  set
    reviewed_at = now(),
    reviewed_by = auth.uid(),
    notes = coalesce(p_notes, notes),
    updated_at = now()
  where id = p_application_id;

  return true;
end;
$$;

revoke all
on function public.complete_internal_application_review(uuid, text)
from public;

grant execute
on function public.complete_internal_application_review(uuid, text)
to authenticated;

notify pgrst, 'reload schema';
