-- ==========================================================================
-- UniMIS Admissions Step 3 refinement
-- Applicant pre-payment editing + subject aliases + eligibility register
-- ==========================================================================

begin;

-- --------------------------------------------------------------------------
-- 1. Canonical WASSCE subject keys.
--    This prevents false "not eligible" results when equivalent labels differ,
--    e.g. "Core Mathematics" vs "Mathematics (Core)".
-- --------------------------------------------------------------------------
create or replace function public.unimis_subject_key(p_subject text)
returns text
language sql
immutable
as $$
  select case regexp_replace(lower(trim(coalesce(p_subject,''))), '[^a-z0-9]+', '', 'g')
    when 'english' then 'englishlanguage'
    when 'englishlanguage' then 'englishlanguage'
    when 'coreenglish' then 'englishlanguage'
    when 'mathematicscore' then 'coremathematics'
    when 'coremathematics' then 'coremathematics'
    when 'coremaths' then 'coremathematics'
    when 'mathematics' then 'coremathematics'
    when 'integratedscience' then 'integratedscience'
    when 'scienceintegrated' then 'integratedscience'
    when 'generalscience' then 'integratedscience'
    when 'socialstudies' then 'socialstudies'
    when 'electivemathematics' then 'electivemathematics'
    when 'mathematicselective' then 'electivemathematics'
    when 'electivemaths' then 'electivemathematics'
    when 'informationandcommunicationtechnology' then 'ict'
    when 'informationcommunicationtechnology' then 'ict'
    when 'ict' then 'ict'
    else regexp_replace(lower(trim(coalesce(p_subject,''))), '[^a-z0-9]+', '', 'g')
  end;
$$;

-- Re-key existing result/rule rows after the improved canonicalisation.
-- Remove alias duplicates first so existing unique constraints cannot block the repair.
with ranked as (
  select id,
         row_number() over (
           partition by qualification_id, public.unimis_subject_key(subject_name)
           order by grade_rank asc, created_at asc
         ) as rn
  from public.applicant_subject_results
)
delete from public.applicant_subject_results r
using ranked x
where r.id=x.id and x.rn>1;

with ranked as (
  select id,
         row_number() over (
           partition by rule_id, subject_group, public.unimis_subject_key(subject_name)
           order by sequence_no asc, created_at asc
         ) as rn
  from public.programme_admission_subject_rules
)
delete from public.programme_admission_subject_rules r
using ranked x
where r.id=x.id and x.rn>1;

update public.applicant_subject_results
set subject_key = public.unimis_subject_key(subject_name),
    updated_at = now()
where subject_key is distinct from public.unimis_subject_key(subject_name);

update public.programme_admission_subject_rules
set subject_key = public.unimis_subject_key(subject_name),
    updated_at = now()
where subject_key is distinct from public.unimis_subject_key(subject_name);

-- --------------------------------------------------------------------------
-- 2. Applicant may edit own qualification before any application is paid or
--    submitted. Structured WASSCE rows are replaced atomically.
-- --------------------------------------------------------------------------
create or replace function public.unimis_applicant_update_exam_qualification(
  p_qualification_id uuid,
  p_qualification_type text,
  p_institution_name text,
  p_examining_body text,
  p_index_number text,
  p_exam_year integer,
  p_exam_sitting text,
  p_subject_results jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_applicant public.applicants%rowtype;
  v_q public.applicant_qualifications%rowtype;
  v_item jsonb;
  v_subject text;
  v_grade text;
  v_rank integer;
  v_core boolean;
begin
  select * into v_applicant
  from public.applicants
  where user_id = auth.uid()
  order by created_at
  limit 1;

  if not found then raise exception 'Applicant profile not found.'; end if;

  select * into v_q
  from public.applicant_qualifications
  where id = p_qualification_id and applicant_id = v_applicant.id;

  if not found then raise exception 'Qualification not found.'; end if;

  if exists (
    select 1 from public.applications a
    where a.applicant_id = v_applicant.id
      and (
        lower(coalesce(a.status,'')) not in ('draft','incomplete','returned')
        or lower(coalesce(a.payment_status,'')) in ('paid','verified')
      )
  ) then
    raise exception 'Qualifications are locked after payment or submission. Contact Admissions for corrections.';
  end if;

  if upper(trim(coalesce(p_qualification_type,''))) <> 'WASSCE' then
    raise exception 'Structured editing currently supports WASSCE.';
  end if;

  if coalesce(trim(p_index_number),'') = '' then raise exception 'Index number is required.'; end if;
  if p_exam_year is null or p_exam_year < 1980 or p_exam_year > extract(year from now())::integer + 1 then
    raise exception 'Enter a valid examination year.';
  end if;
  if jsonb_typeof(coalesce(p_subject_results,'[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_subject_results,'[]'::jsonb)) < 6 then
    raise exception 'Enter at least six WASSCE subject results.';
  end if;

  update public.applicant_qualifications
  set qualification_type = upper(trim(p_qualification_type)),
      institution_name = nullif(trim(p_institution_name),''),
      examining_body = coalesce(nullif(trim(p_examining_body),''),'WAEC'),
      index_number = trim(p_index_number),
      completion_year = p_exam_year,
      exam_sitting = nullif(trim(p_exam_sitting),''),
      details = coalesce(details,'{}'::jsonb) || jsonb_build_object(
        'structured', true,
        'exam_sitting', nullif(trim(p_exam_sitting),''),
        'subject_results', p_subject_results
      ),
      verification_status = 'unverified',
      verification_source = 'manual',
      verification_reference = null,
      verification_notes = null,
      verified_at = null,
      verified_by = null,
      updated_at = now()
  where id = p_qualification_id;

  delete from public.applicant_subject_results where qualification_id = p_qualification_id;

  for v_item in select value from jsonb_array_elements(p_subject_results)
  loop
    v_subject := trim(coalesce(v_item->>'subject',''));
    v_grade := upper(trim(coalesce(v_item->>'grade','')));
    v_rank := public.unimis_grade_rank(v_grade);
    v_core := case when v_item ? 'is_core' then (v_item->>'is_core')::boolean else null end;

    if v_subject = '' then raise exception 'Every result row must contain a subject.'; end if;
    if v_rank is null then raise exception 'Invalid grade % for %.', v_grade, v_subject; end if;

    insert into public.applicant_subject_results(
      institution_id, applicant_id, qualification_id,
      subject_name, subject_key, grade, grade_rank, is_core
    ) values (
      v_applicant.institution_id, v_applicant.id, p_qualification_id,
      v_subject, public.unimis_subject_key(v_subject), v_grade, v_rank, v_core
    );
  end loop;

  return p_qualification_id;
end;
$$;

grant execute on function public.unimis_applicant_update_exam_qualification(uuid,text,text,text,text,integer,text,jsonb)
  to authenticated, service_role;

create or replace function public.unimis_applicant_update_qualification(
  p_qualification_id uuid,
  p_qualification_type text,
  p_institution_name text,
  p_examining_body text,
  p_index_number text,
  p_completion_year integer,
  p_overall_result text,
  p_details jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_applicant public.applicants%rowtype;
begin
  select * into v_applicant from public.applicants where user_id = auth.uid() order by created_at limit 1;
  if not found then raise exception 'Applicant profile not found.'; end if;

  if not exists (select 1 from public.applicant_qualifications where id=p_qualification_id and applicant_id=v_applicant.id) then
    raise exception 'Qualification not found.';
  end if;

  if exists (
    select 1 from public.applications a
    where a.applicant_id = v_applicant.id
      and (lower(coalesce(a.status,'')) not in ('draft','incomplete','returned')
           or lower(coalesce(a.payment_status,'')) in ('paid','verified'))
  ) then
    raise exception 'Qualifications are locked after payment or submission. Contact Admissions for corrections.';
  end if;

  update public.applicant_qualifications
  set qualification_type=trim(p_qualification_type), institution_name=nullif(trim(p_institution_name),''),
      examining_body=nullif(trim(p_examining_body),''), index_number=nullif(trim(p_index_number),''),
      completion_year=p_completion_year, overall_result=nullif(trim(p_overall_result),''),
      details=coalesce(p_details,'{}'::jsonb), updated_at=now()
  where id=p_qualification_id;

  return p_qualification_id;
end;
$$;

grant execute on function public.unimis_applicant_update_qualification(uuid,text,text,text,text,integer,text,jsonb)
  to authenticated, service_role;

create or replace function public.unimis_applicant_delete_qualification(p_qualification_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare v_applicant public.applicants%rowtype;
begin
  select * into v_applicant from public.applicants where user_id=auth.uid() order by created_at limit 1;
  if not found then raise exception 'Applicant profile not found.'; end if;
  if exists (
    select 1 from public.applications a where a.applicant_id=v_applicant.id
      and (lower(coalesce(a.status,'')) not in ('draft','incomplete','returned')
           or lower(coalesce(a.payment_status,'')) in ('paid','verified'))
  ) then
    raise exception 'Qualifications are locked after payment or submission.';
  end if;
  delete from public.applicant_qualifications where id=p_qualification_id and applicant_id=v_applicant.id;
  return found;
end;
$$;

grant execute on function public.unimis_applicant_delete_qualification(uuid) to authenticated, service_role;

-- --------------------------------------------------------------------------
-- 3. Applicant document deletion/replacement before payment/submission.
-- --------------------------------------------------------------------------
create or replace function public.unimis_applicant_delete_document(p_document_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_applicant public.applicants%rowtype;
  v_doc public.application_documents%rowtype;
  v_app public.applications%rowtype;
begin
  select * into v_applicant from public.applicants where user_id=auth.uid() order by created_at limit 1;
  if not found then raise exception 'Applicant profile not found.'; end if;

  select d.* into v_doc
  from public.application_documents d
  join public.applications a on a.id=d.application_id
  where d.id=p_document_id and a.applicant_id=v_applicant.id;
  if not found then raise exception 'Document not found.'; end if;

  select * into v_app from public.applications where id=v_doc.application_id;
  if lower(coalesce(v_app.status,'')) not in ('draft','incomplete','returned')
     or lower(coalesce(v_app.payment_status,'')) in ('paid','verified') then
    raise exception 'Documents are locked after payment or submission. Contact Admissions for corrections.';
  end if;

  delete from public.application_documents where id=p_document_id;
  return v_doc.storage_path;
end;
$$;

grant execute on function public.unimis_applicant_delete_document(uuid) to authenticated, service_role;

-- Allow applicants to remove their own uploaded object during pre-payment edits.
drop policy if exists "Applicants delete own admission documents" on storage.objects;
create policy "Applicants delete own admission documents"
on storage.objects for delete to authenticated
using (
  bucket_id = 'admission-documents'
  and exists (
    select 1
    from public.application_documents d
    join public.applications ap on ap.id = d.application_id
    join public.applicants a on a.id = ap.applicant_id
    where d.storage_path = name and a.user_id = auth.uid()
  )
);

-- --------------------------------------------------------------------------
-- 4. Applicant programme-choice editing before payment/submission.
-- --------------------------------------------------------------------------
create or replace function public.unimis_applicant_update_application_choices(
  p_application_id uuid,
  p_programme_ids uuid[]
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_app public.applications%rowtype;
  v_applicant public.applicants%rowtype;
  v_cycle public.admission_cycles%rowtype;
  v_programme_id uuid;
  v_order integer := 1;
begin
  select * into v_applicant from public.applicants where user_id=auth.uid() order by created_at limit 1;
  if not found then raise exception 'Applicant profile not found.'; end if;

  select * into v_app from public.applications where id=p_application_id and applicant_id=v_applicant.id;
  if not found then raise exception 'Application not found.'; end if;

  if lower(coalesce(v_app.status,'')) not in ('draft','incomplete','returned')
     or lower(coalesce(v_app.payment_status,'')) in ('paid','verified') then
    raise exception 'Programme choices are locked after payment or submission.';
  end if;

  select * into v_cycle from public.admission_cycles where id=v_app.admission_cycle_id;
  if coalesce(array_length(p_programme_ids,1),0) < 1 then raise exception 'Select at least one programme.'; end if;
  if array_length(p_programme_ids,1) > coalesce(v_cycle.max_programme_choices,3) then
    raise exception 'Too many programme choices for this admission cycle.';
  end if;
  if (select count(distinct x) from unnest(p_programme_ids) x) <> array_length(p_programme_ids,1) then
    raise exception 'Programme choices must be different.';
  end if;

  foreach v_programme_id in array p_programme_ids loop
    if not exists (
      select 1 from public.programmes p
      where p.id=v_programme_id and p.institution_id=v_app.institution_id
        and (coalesce(p.admission_level,'both')='both' or p.admission_level=v_app.admission_level)
        and (v_app.applicant_category <> 'local' or coalesce(p.accepts_local,true))
        and (v_app.applicant_category <> 'international' or coalesce(p.accepts_international,true))
    ) then raise exception 'One selected programme is not available for this application route.'; end if;
  end loop;

  delete from public.application_choices where application_id=p_application_id;
  foreach v_programme_id in array p_programme_ids loop
    insert into public.application_choices(institution_id,application_id,programme_id,choice_order)
    values(v_app.institution_id,p_application_id,v_programme_id,v_order);
    v_order := v_order + 1;
  end loop;

  update public.applications set updated_at=now() where id=p_application_id;
  return true;
end;
$$;

grant execute on function public.unimis_applicant_update_application_choices(uuid,uuid[]) to authenticated, service_role;

-- --------------------------------------------------------------------------
-- 5. Eligibility register for all applications/programme choices.
--    Uses the same evaluator as the individual Review screen.
-- --------------------------------------------------------------------------
create or replace function public.unimis_admissions_eligibility_register(
  p_institution_id uuid,
  p_admission_cycle_id uuid default null
)
returns table (
  application_id uuid,
  application_number text,
  applicant_id uuid,
  applicant_name text,
  applicant_category text,
  application_status text,
  admission_cycle_id uuid,
  admission_cycle_name text,
  choice_order integer,
  programme_id uuid,
  programme_code text,
  programme_name text,
  eligibility_status text,
  aggregate integer,
  max_aggregate integer,
  qualification_verified boolean,
  message text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_app record;
  v_eval jsonb;
  v_choice jsonb;
begin
  if auth.role() <> 'service_role' and not public.unimis_is_institution_member(p_institution_id) then
    raise exception 'Not authorized.' using errcode='42501';
  end if;

  for v_app in
    select a.id, a.application_number, a.applicant_id, a.applicant_category, a.status,
           a.admission_cycle_id, c.name as cycle_name,
           trim(concat_ws(' ', ap.first_name, ap.middle_name, ap.last_name)) as full_name
    from public.applications a
    join public.applicants ap on ap.id=a.applicant_id
    join public.admission_cycles c on c.id=a.admission_cycle_id
    where a.institution_id=p_institution_id
      and (p_admission_cycle_id is null or a.admission_cycle_id=p_admission_cycle_id)
    order by a.created_at desc
  loop
    v_eval := public.unimis_evaluate_application_eligibility(v_app.id);
    for v_choice in select value from jsonb_array_elements(coalesce(v_eval->'choices','[]'::jsonb))
    loop
      application_id := v_app.id;
      application_number := v_app.application_number;
      applicant_id := v_app.applicant_id;
      applicant_name := v_app.full_name;
      applicant_category := v_app.applicant_category;
      application_status := v_app.status;
      admission_cycle_id := v_app.admission_cycle_id;
      admission_cycle_name := v_app.cycle_name;
      choice_order := nullif(v_choice->>'choice_order','')::integer;
      programme_id := nullif(v_choice->>'programme_id','')::uuid;
      programme_code := v_choice->>'programme_code';
      programme_name := v_choice->>'programme_name';
      eligibility_status := v_choice->>'status';
      aggregate := nullif(v_choice->>'aggregate','')::integer;
      max_aggregate := nullif(v_choice->>'max_aggregate','')::integer;
      qualification_verified := coalesce((v_choice->>'qualification_verified')::boolean,false);
      message := v_choice->>'message';
      return next;
    end loop;
  end loop;
end;
$$;

grant execute on function public.unimis_admissions_eligibility_register(uuid,uuid) to authenticated, service_role;

commit;
