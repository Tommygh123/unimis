-- ============================================================================
-- UniMIS Admissions Step 3
-- Structured WASSCE results + configurable programme admission rules
-- + automatic academic eligibility assessment
-- ============================================================================

begin;

create extension if not exists pgcrypto;

-- --------------------------------------------------------------------------
-- 1. Extend applicant qualifications with result-verification metadata.
--    The qualification remains the parent record for each exam sitting.
-- --------------------------------------------------------------------------
alter table public.applicant_qualifications
  add column if not exists exam_sitting text,
  add column if not exists verification_status text,
  add column if not exists verification_source text,
  add column if not exists verification_reference text,
  add column if not exists verification_notes text,
  add column if not exists verified_at timestamptz,
  add column if not exists verified_by uuid;

update public.applicant_qualifications
set verification_status = coalesce(verification_status, 'unverified'),
    verification_source = coalesce(verification_source, 'manual')
where verification_status is null
   or verification_source is null;

alter table public.applicant_qualifications
  alter column verification_status set default 'unverified',
  alter column verification_source set default 'manual';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'applicant_qualifications_verification_status_chk'
      and conrelid = 'public.applicant_qualifications'::regclass
  ) then
    alter table public.applicant_qualifications
      add constraint applicant_qualifications_verification_status_chk
      check (verification_status in ('unverified','pending','verified','mismatch','rejected'));
  end if;
end $$;

-- --------------------------------------------------------------------------
-- 2. Structured subjects/grades for each qualification/exam sitting.
--    This is deliberately separate from the uploaded certificate/result slip.
-- --------------------------------------------------------------------------
create table if not exists public.applicant_subject_results (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  applicant_id uuid not null references public.applicants(id) on delete cascade,
  qualification_id uuid not null references public.applicant_qualifications(id) on delete cascade,
  subject_name text not null,
  subject_key text not null,
  grade text not null,
  grade_rank integer not null,
  is_core boolean,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (qualification_id, subject_key)
);

create index if not exists applicant_subject_results_applicant_idx
  on public.applicant_subject_results(applicant_id);
create index if not exists applicant_subject_results_qualification_idx
  on public.applicant_subject_results(qualification_id);
create index if not exists applicant_subject_results_subject_idx
  on public.applicant_subject_results(applicant_id, subject_key, grade_rank);

-- --------------------------------------------------------------------------
-- 3. Programme admission rule header.
--    Phase 1 focuses on Ghanaian WASSCE style subject/aggregate rules.
-- --------------------------------------------------------------------------
create table if not exists public.programme_admission_rules (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  admission_cycle_id uuid references public.admission_cycles(id) on delete cascade,
  programme_id uuid not null references public.programmes(id) on delete cascade,
  qualification_type text not null default 'WASSCE',
  max_aggregate integer,
  minimum_elective_passes integer not null default 3,
  default_max_grade_rank integer not null default 6,
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists programme_admission_rules_unique_active_scope
  on public.programme_admission_rules(
    institution_id,
    programme_id,
    coalesce(admission_cycle_id, '00000000-0000-0000-0000-000000000000'::uuid),
    lower(qualification_type)
  );

create table if not exists public.programme_admission_subject_rules (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  rule_id uuid not null references public.programme_admission_rules(id) on delete cascade,
  subject_name text not null,
  subject_key text not null,
  subject_group text not null default 'required',
  max_grade_rank integer,
  sequence_no integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(rule_id, subject_key, subject_group)
);

create index if not exists programme_admission_subject_rules_rule_idx
  on public.programme_admission_subject_rules(rule_id, subject_group, sequence_no);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'programme_admission_subject_group_chk'
      and conrelid = 'public.programme_admission_subject_rules'::regclass
  ) then
    alter table public.programme_admission_subject_rules
      add constraint programme_admission_subject_group_chk
      check (subject_group in ('required','elective_pool'));
  end if;
end $$;

-- --------------------------------------------------------------------------
-- 4. Helpers.
-- --------------------------------------------------------------------------
create or replace function public.unimis_subject_key(p_subject text)
returns text
language sql
immutable
as $$
  select regexp_replace(lower(trim(coalesce(p_subject,''))), '[^a-z0-9]+', '', 'g');
$$;

create or replace function public.unimis_grade_rank(p_grade text)
returns integer
language sql
immutable
as $$
  select case upper(trim(coalesce(p_grade,'')))
    when 'A1' then 1
    when 'B2' then 2
    when 'B3' then 3
    when 'C4' then 4
    when 'C5' then 5
    when 'C6' then 6
    when 'D7' then 7
    when 'E8' then 8
    when 'F9' then 9
    else null
  end;
$$;

-- --------------------------------------------------------------------------
-- 5. Applicant RPC: create a WASSCE/SSSCE sitting and structured subjects.
--    p_subject_results example:
--    [{"subject":"English Language","grade":"B3","is_core":true}, ...]
-- --------------------------------------------------------------------------
create or replace function public.unimis_applicant_add_exam_qualification(
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
  v_qualification_id uuid;
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

  if not found then
    raise exception 'Applicant profile not found.';
  end if;

  if upper(trim(coalesce(p_qualification_type,''))) <> 'WASSCE' then
    raise exception 'Structured exam entry currently supports WASSCE. Other qualification types remain available through the general qualification form.';
  end if;

  if coalesce(trim(p_index_number),'') = '' then
    raise exception 'Index number is required.';
  end if;

  if p_exam_year is null or p_exam_year < 1980 or p_exam_year > extract(year from now())::integer + 1 then
    raise exception 'Enter a valid examination year.';
  end if;

  if jsonb_typeof(coalesce(p_subject_results,'[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_subject_results,'[]'::jsonb)) = 0 then
    raise exception 'Enter at least one subject result.';
  end if;

  insert into public.applicant_qualifications(
    institution_id, applicant_id, qualification_type, institution_name,
    examining_body, index_number, completion_year, overall_result, details,
    exam_sitting, verification_status, verification_source
  )
  values(
    v_applicant.institution_id,
    v_applicant.id,
    upper(trim(p_qualification_type)),
    nullif(trim(p_institution_name),''),
    coalesce(nullif(trim(p_examining_body),''),'WAEC'),
    trim(p_index_number),
    p_exam_year,
    null,
    jsonb_build_object(
      'structured', true,
      'exam_sitting', nullif(trim(p_exam_sitting),''),
      'subject_results', coalesce(p_subject_results,'[]'::jsonb)
    ),
    nullif(trim(p_exam_sitting),''),
    'unverified',
    'manual'
  )
  returning id into v_qualification_id;

  for v_item in
    select value from jsonb_array_elements(p_subject_results)
  loop
    v_subject := trim(coalesce(v_item->>'subject',''));
    v_grade := upper(trim(coalesce(v_item->>'grade','')));
    v_rank := public.unimis_grade_rank(v_grade);
    v_core := case
      when v_item ? 'is_core' then (v_item->>'is_core')::boolean
      else null
    end;

    if v_subject = '' then
      raise exception 'Every result row must contain a subject.';
    end if;
    if v_rank is null then
      raise exception 'Invalid grade % for %.', v_grade, v_subject;
    end if;

    insert into public.applicant_subject_results(
      institution_id, applicant_id, qualification_id,
      subject_name, subject_key, grade, grade_rank, is_core
    )
    values(
      v_applicant.institution_id,
      v_applicant.id,
      v_qualification_id,
      v_subject,
      public.unimis_subject_key(v_subject),
      v_grade,
      v_rank,
      v_core
    )
    on conflict (qualification_id, subject_key)
    do update set
      subject_name = excluded.subject_name,
      grade = excluded.grade,
      grade_rank = excluded.grade_rank,
      is_core = excluded.is_core,
      updated_at = now();
  end loop;

  return v_qualification_id;
end;
$$;

revoke all on function public.unimis_applicant_add_exam_qualification(text,text,text,text,integer,text,jsonb) from public;
grant execute on function public.unimis_applicant_add_exam_qualification(text,text,text,text,integer,text,jsonb)
  to authenticated, service_role;

-- --------------------------------------------------------------------------
-- 6. Staff result verification RPC. Future WAEC API integration can call the
--    same metadata model using service_role and verification_source='waec_api'.
-- --------------------------------------------------------------------------
create or replace function public.unimis_verify_applicant_qualification(
  p_qualification_id uuid,
  p_status text,
  p_source text default 'manual',
  p_reference text default null,
  p_notes text default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_q public.applicant_qualifications%rowtype;
begin
  if p_status not in ('unverified','pending','verified','mismatch','rejected') then
    raise exception 'Invalid qualification verification status.';
  end if;

  select * into v_q
  from public.applicant_qualifications
  where id = p_qualification_id;

  if not found then
    raise exception 'Qualification not found.';
  end if;

  if auth.role() <> 'service_role'
     and not public.unimis_is_institution_member(v_q.institution_id) then
    raise exception 'Not authorized.' using errcode='42501';
  end if;

  update public.applicant_qualifications
  set verification_status = p_status,
      verification_source = coalesce(nullif(trim(p_source),''),'manual'),
      verification_reference = nullif(trim(p_reference),''),
      verification_notes = nullif(trim(p_notes),''),
      verified_at = case when p_status = 'verified' then now() else null end,
      verified_by = case when p_status = 'verified' then auth.uid() else null end,
      updated_at = now()
  where id = p_qualification_id;

  return true;
end;
$$;

revoke all on function public.unimis_verify_applicant_qualification(uuid,text,text,text,text) from public;
grant execute on function public.unimis_verify_applicant_qualification(uuid,text,text,text,text)
  to authenticated, service_role;

-- --------------------------------------------------------------------------
-- 7. Staff rule-save RPC. Replaces the complete subject set atomically.
--    subject rule JSON rows:
--    {"subject_name":"English Language","subject_group":"required","max_grade_rank":6}
-- --------------------------------------------------------------------------
create or replace function public.unimis_save_programme_admission_rule(
  p_institution_id uuid,
  p_programme_id uuid,
  p_admission_cycle_id uuid,
  p_qualification_type text,
  p_max_aggregate integer,
  p_minimum_elective_passes integer,
  p_default_max_grade_rank integer,
  p_notes text,
  p_subject_rules jsonb,
  p_rule_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rule_id uuid;
  v_item jsonb;
  v_subject text;
  v_group text;
  v_max_rank integer;
  v_sequence integer := 10;
begin
  if auth.role() <> 'service_role'
     and not public.unimis_is_institution_member(p_institution_id) then
    raise exception 'Not authorized.' using errcode='42501';
  end if;

  if not exists (
    select 1 from public.programmes
    where id = p_programme_id and institution_id = p_institution_id
  ) then
    raise exception 'Programme does not belong to this institution.';
  end if;

  if p_admission_cycle_id is not null and not exists (
    select 1 from public.admission_cycles
    where id = p_admission_cycle_id and institution_id = p_institution_id
  ) then
    raise exception 'Admission cycle does not belong to this institution.';
  end if;

  if coalesce(p_minimum_elective_passes,0) < 0 then
    raise exception 'Minimum elective passes cannot be negative.';
  end if;

  if coalesce(p_default_max_grade_rank,0) not between 1 and 9 then
    raise exception 'Default maximum grade rank must be between 1 and 9.';
  end if;

  if p_rule_id is null then
    insert into public.programme_admission_rules(
      institution_id, admission_cycle_id, programme_id, qualification_type,
      max_aggregate, minimum_elective_passes, default_max_grade_rank,
      notes, is_active
    )
    values(
      p_institution_id, p_admission_cycle_id, p_programme_id,
      upper(trim(coalesce(p_qualification_type,'WASSCE'))),
      p_max_aggregate, coalesce(p_minimum_elective_passes,3),
      coalesce(p_default_max_grade_rank,6), nullif(trim(p_notes),''), true
    )
    returning id into v_rule_id;
  else
    update public.programme_admission_rules
    set admission_cycle_id = p_admission_cycle_id,
        programme_id = p_programme_id,
        qualification_type = upper(trim(coalesce(p_qualification_type,'WASSCE'))),
        max_aggregate = p_max_aggregate,
        minimum_elective_passes = coalesce(p_minimum_elective_passes,3),
        default_max_grade_rank = coalesce(p_default_max_grade_rank,6),
        notes = nullif(trim(p_notes),''),
        is_active = true,
        updated_at = now()
    where id = p_rule_id
      and institution_id = p_institution_id
    returning id into v_rule_id;

    if v_rule_id is null then
      raise exception 'Admission rule not found.';
    end if;
  end if;

  delete from public.programme_admission_subject_rules
  where rule_id = v_rule_id;

  for v_item in
    select value from jsonb_array_elements(coalesce(p_subject_rules,'[]'::jsonb))
  loop
    v_subject := trim(coalesce(v_item->>'subject_name',''));
    v_group := coalesce(nullif(trim(v_item->>'subject_group'),''),'required');
    v_max_rank := coalesce(
      nullif(v_item->>'max_grade_rank','')::integer,
      coalesce(p_default_max_grade_rank,6)
    );

    if v_subject = '' then continue; end if;
    if v_group not in ('required','elective_pool') then
      raise exception 'Invalid subject group %.', v_group;
    end if;

    insert into public.programme_admission_subject_rules(
      institution_id, rule_id, subject_name, subject_key,
      subject_group, max_grade_rank, sequence_no
    )
    values(
      p_institution_id, v_rule_id, v_subject,
      public.unimis_subject_key(v_subject),
      v_group, v_max_rank, v_sequence
    );

    v_sequence := v_sequence + 10;
  end loop;

  return v_rule_id;
end;
$$;

revoke all on function public.unimis_save_programme_admission_rule(uuid,uuid,uuid,text,integer,integer,integer,text,jsonb,uuid) from public;
grant execute on function public.unimis_save_programme_admission_rule(uuid,uuid,uuid,text,integer,integer,integer,text,jsonb,uuid)
  to authenticated, service_role;

-- --------------------------------------------------------------------------
-- 8. Eligibility evaluator.
--    Returns one result for each programme choice. Result is academic/provisional
--    until the qualification itself is officially verified.
-- --------------------------------------------------------------------------
create or replace function public.unimis_evaluate_application_eligibility(
  p_application_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_app public.applications%rowtype;
  v_choice record;
  v_rule public.programme_admission_rules%rowtype;
  v_required_total integer;
  v_required_passed integer;
  v_elective_passed integer;
  v_core_sum integer;
  v_elective_sum integer;
  v_aggregate integer;
  v_results_verified boolean;
  v_failed_required jsonb;
  v_elective_detail jsonb;
  v_rows jsonb := '[]'::jsonb;
  v_status text;
begin
  select * into v_app
  from public.applications
  where id = p_application_id;

  if not found then
    raise exception 'Application not found.';
  end if;

  if auth.role() <> 'service_role'
     and not public.unimis_is_institution_member(v_app.institution_id)
     and not public.unimis_applicant_owns_application(p_application_id) then
    raise exception 'Not authorized.' using errcode='42501';
  end if;

  for v_choice in
    select ch.choice_order, p.id as programme_id, p.code, p.name
    from public.application_choices ch
    join public.programmes p on p.id = ch.programme_id
    where ch.application_id = p_application_id
    order by ch.choice_order
  loop
    select r.* into v_rule
    from public.programme_admission_rules r
    where r.institution_id = v_app.institution_id
      and r.programme_id = v_choice.programme_id
      and r.is_active = true
      and upper(r.qualification_type) in (
        select upper(q.qualification_type)
        from public.applicant_qualifications q
        where q.applicant_id = v_app.applicant_id
      )
      and (r.admission_cycle_id = v_app.admission_cycle_id or r.admission_cycle_id is null)
    order by (r.admission_cycle_id = v_app.admission_cycle_id) desc,
             r.updated_at desc
    limit 1;

    if not found then
      v_rows := v_rows || jsonb_build_array(jsonb_build_object(
        'choice_order', v_choice.choice_order,
        'programme_id', v_choice.programme_id,
        'programme_code', v_choice.code,
        'programme_name', v_choice.name,
        'status', 'not_configured',
        'qualification_verified', false,
        'aggregate', null,
        'message', 'No active admission rule is configured for this programme and qualification.'
      ));
      continue;
    end if;

    with best as (
      select sr.subject_key,
             min(sr.grade_rank) as grade_rank
      from public.applicant_subject_results sr
      join public.applicant_qualifications q on q.id = sr.qualification_id
      where sr.applicant_id = v_app.applicant_id
        and upper(q.qualification_type) = upper(v_rule.qualification_type)
      group by sr.subject_key
    ), required_rules as (
      select s.*,
             coalesce(s.max_grade_rank, v_rule.default_max_grade_rank) as threshold
      from public.programme_admission_subject_rules s
      where s.rule_id = v_rule.id
        and s.subject_group = 'required'
    )
    select
      count(*)::integer,
      count(*) filter (where b.grade_rank is not null and b.grade_rank <= rr.threshold)::integer,
      coalesce(sum(b.grade_rank) filter (where b.grade_rank is not null and b.grade_rank <= rr.threshold),0)::integer,
      coalesce(jsonb_agg(jsonb_build_object(
        'subject',rr.subject_name,
        'max_grade_rank',rr.threshold,
        'best_grade_rank',b.grade_rank
      )) filter (where b.grade_rank is null or b.grade_rank > rr.threshold),'[]'::jsonb)
    into v_required_total, v_required_passed, v_core_sum, v_failed_required
    from required_rules rr
    left join best b on b.subject_key = rr.subject_key;

    with best as (
      select sr.subject_key,
             min(sr.grade_rank) as grade_rank,
             (array_agg(sr.grade order by sr.grade_rank asc))[1] as grade
      from public.applicant_subject_results sr
      join public.applicant_qualifications q on q.id = sr.qualification_id
      where sr.applicant_id = v_app.applicant_id
        and upper(q.qualification_type) = upper(v_rule.qualification_type)
      group by sr.subject_key
    ), pool as (
      select s.subject_name, s.subject_key,
             coalesce(s.max_grade_rank, v_rule.default_max_grade_rank) as threshold,
             b.grade_rank, b.grade
      from public.programme_admission_subject_rules s
      left join best b on b.subject_key = s.subject_key
      where s.rule_id = v_rule.id
        and s.subject_group = 'elective_pool'
    ), passed as (
      select * from pool
      where grade_rank is not null and grade_rank <= threshold
      order by grade_rank asc, subject_name
    ), chosen as (
      select * from passed
      limit greatest(v_rule.minimum_elective_passes,0)
    )
    select
      (select count(*)::integer from passed),
      coalesce((select sum(grade_rank)::integer from chosen),0),
      coalesce((select jsonb_agg(jsonb_build_object(
        'subject',subject_name,'grade',grade,'grade_rank',grade_rank,'max_grade_rank',threshold
      ) order by grade_rank,subject_name) from passed),'[]'::jsonb)
    into v_elective_passed, v_elective_sum, v_elective_detail;

    v_aggregate := case
      when v_required_total = v_required_passed
       and v_elective_passed >= v_rule.minimum_elective_passes
      then v_core_sum + v_elective_sum
      else null
    end;

    select not exists (
      select 1
      from public.applicant_qualifications q
      where q.applicant_id = v_app.applicant_id
        and upper(q.qualification_type) = upper(v_rule.qualification_type)
        and exists (
          select 1 from public.applicant_subject_results sr
          where sr.qualification_id = q.id
        )
        and coalesce(q.verification_status,'unverified') <> 'verified'
    )
    and exists (
      select 1
      from public.applicant_qualifications q
      where q.applicant_id = v_app.applicant_id
        and upper(q.qualification_type) = upper(v_rule.qualification_type)
        and exists (
          select 1 from public.applicant_subject_results sr
          where sr.qualification_id = q.id
        )
    )
    into v_results_verified;

    if v_required_total = 0
       and v_rule.minimum_elective_passes = 0 then
      v_status := 'not_configured';
    elsif v_required_passed < v_required_total
       or v_elective_passed < v_rule.minimum_elective_passes then
      v_status := 'not_eligible';
    elsif v_rule.max_aggregate is not null
       and v_aggregate is not null
       and v_aggregate > v_rule.max_aggregate then
      v_status := 'not_eligible';
    elsif v_aggregate is null then
      v_status := 'incomplete';
    else
      v_status := 'eligible';
    end if;

    v_rows := v_rows || jsonb_build_array(jsonb_build_object(
      'choice_order', v_choice.choice_order,
      'programme_id', v_choice.programme_id,
      'programme_code', v_choice.code,
      'programme_name', v_choice.name,
      'rule_id', v_rule.id,
      'qualification_type', v_rule.qualification_type,
      'status', v_status,
      'qualification_verified', v_results_verified,
      'aggregate', v_aggregate,
      'max_aggregate', v_rule.max_aggregate,
      'required_subjects_total', v_required_total,
      'required_subjects_passed', v_required_passed,
      'minimum_elective_passes', v_rule.minimum_elective_passes,
      'elective_passes', v_elective_passed,
      'failed_required_subjects', coalesce(v_failed_required,'[]'::jsonb),
      'passing_electives', coalesce(v_elective_detail,'[]'::jsonb),
      'message', case
        when v_status = 'eligible' and v_results_verified then 'Academically eligible using verified results.'
        when v_status = 'eligible' then 'Academically eligible provisionally; result verification is still pending.'
        when v_status = 'not_eligible' then 'Entered results do not satisfy the configured programme rule.'
        when v_status = 'incomplete' then 'More structured subject results are required.'
        else 'Admission rule requires configuration.'
      end
    ));
  end loop;

  return jsonb_build_object(
    'application_id', p_application_id,
    'evaluated_at', now(),
    'choices', v_rows
  );
end;
$$;

revoke all on function public.unimis_evaluate_application_eligibility(uuid) from public;
grant execute on function public.unimis_evaluate_application_eligibility(uuid)
  to authenticated, service_role;

-- --------------------------------------------------------------------------
-- 9. RLS for new tables.
-- --------------------------------------------------------------------------
alter table public.applicant_subject_results enable row level security;
alter table public.programme_admission_rules enable row level security;
alter table public.programme_admission_subject_rules enable row level security;

drop policy if exists "Institution members manage applicant subject results" on public.applicant_subject_results;
create policy "Institution members manage applicant subject results"
on public.applicant_subject_results
for all to authenticated
using (public.unimis_is_institution_member(institution_id))
with check (public.unimis_is_institution_member(institution_id));

drop policy if exists "Applicants read own subject results" on public.applicant_subject_results;
create policy "Applicants read own subject results"
on public.applicant_subject_results
for select to authenticated
using (
  exists (
    select 1 from public.applicants a
    where a.id = applicant_id and a.user_id = auth.uid()
  )
);

drop policy if exists "Institution members manage programme admission rules" on public.programme_admission_rules;
create policy "Institution members manage programme admission rules"
on public.programme_admission_rules
for all to authenticated
using (public.unimis_is_institution_member(institution_id))
with check (public.unimis_is_institution_member(institution_id));

drop policy if exists "Institution members manage programme admission subject rules" on public.programme_admission_subject_rules;
create policy "Institution members manage programme admission subject rules"
on public.programme_admission_subject_rules
for all to authenticated
using (public.unimis_is_institution_member(institution_id))
with check (public.unimis_is_institution_member(institution_id));

-- Staff/browser reads use RLS. Applicant writes use the definer RPC above.
grant select, insert, update, delete on public.applicant_subject_results to authenticated, service_role;
grant select, insert, update, delete on public.programme_admission_rules to authenticated, service_role;
grant select, insert, update, delete on public.programme_admission_subject_rules to authenticated, service_role;

commit;

-- Verification examples after migration:
-- select * from public.programme_admission_rules;
-- select * from public.programme_admission_subject_rules;
-- select * from public.applicant_subject_results;
-- select public.unimis_evaluate_application_eligibility('<application-uuid>');
