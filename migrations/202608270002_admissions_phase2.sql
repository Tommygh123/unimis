-- ============================================================================
-- UniMIS Admissions Phase 2
-- Local / International + Undergraduate / Postgraduate
-- Payment rules + document requirements + review history + offers + conversion
--
-- IMPORTANT
-- 1. This is an EXTENSION migration for the existing UniMIS admissions schema.
-- 2. It does not drop or recreate existing admissions/student tables.
-- 3. It intentionally leaves existing RLS policies untouched until the separate
--    RLS audit is completed.
-- ============================================================================

begin;

create extension if not exists pgcrypto;

-- ============================================================================
-- A. EXTEND ADMISSION CYCLES
-- ============================================================================

alter table public.admission_cycles
    add column if not exists admission_level text;

alter table public.admission_cycles
    add column if not exists applicant_scope text;

alter table public.admission_cycles
    add column if not exists max_programme_choices integer;

alter table public.admission_cycles
    add column if not exists payment_required boolean;

alter table public.admission_cycles
    add column if not exists allow_draft_before_payment boolean;

alter table public.admission_cycles
    add column if not exists application_instructions text;

update public.admission_cycles
set
    admission_level = coalesce(admission_level, 'undergraduate'),
    applicant_scope = coalesce(applicant_scope, 'both'),
    max_programme_choices = coalesce(max_programme_choices, 3),
    payment_required = coalesce(payment_required, true),
    allow_draft_before_payment = coalesce(allow_draft_before_payment, true)
where admission_level is null
   or applicant_scope is null
   or max_programme_choices is null
   or payment_required is null
   or allow_draft_before_payment is null;

alter table public.admission_cycles
    alter column admission_level set default 'undergraduate',
    alter column applicant_scope set default 'both',
    alter column max_programme_choices set default 3,
    alter column payment_required set default true,
    alter column allow_draft_before_payment set default true;

do $$
begin
    if not exists (
        select 1 from pg_constraint
        where conname = 'admission_cycles_level_chk'
          and conrelid = 'public.admission_cycles'::regclass
    ) then
        alter table public.admission_cycles
        add constraint admission_cycles_level_chk
        check (admission_level in ('undergraduate','postgraduate','both'));
    end if;

    if not exists (
        select 1 from pg_constraint
        where conname = 'admission_cycles_scope_chk'
          and conrelid = 'public.admission_cycles'::regclass
    ) then
        alter table public.admission_cycles
        add constraint admission_cycles_scope_chk
        check (applicant_scope in ('local','international','both'));
    end if;

    if not exists (
        select 1 from pg_constraint
        where conname = 'admission_cycles_choices_chk'
          and conrelid = 'public.admission_cycles'::regclass
    ) then
        alter table public.admission_cycles
        add constraint admission_cycles_choices_chk
        check (max_programme_choices between 1 and 10);
    end if;
end $$;

-- ============================================================================
-- B. EXTEND APPLICANT PROFILE
-- ============================================================================

alter table public.applicants
    add column if not exists applicant_category text;

alter table public.applicants
    add column if not exists country_of_birth text;

alter table public.applicants
    add column if not exists national_id_type text;

alter table public.applicants
    add column if not exists national_id_number text;

alter table public.applicants
    add column if not exists passport_number text;

alter table public.applicants
    add column if not exists passport_expiry_date date;

alter table public.applicants
    add column if not exists residency_status text;

update public.applicants
set applicant_category =
    case
        when lower(coalesce(nationality,'')) in ('ghanaian','ghana')
             then 'local'
        else 'international'
    end
where applicant_category is null;

do $$
begin
    if not exists (
        select 1 from pg_constraint
        where conname = 'applicants_category_chk'
          and conrelid = 'public.applicants'::regclass
    ) then
        alter table public.applicants
        add constraint applicants_category_chk
        check (applicant_category in ('local','international'));
    end if;
end $$;

create index if not exists idx_applicants_category
    on public.applicants (applicant_category);

-- ============================================================================
-- C. EXTEND APPLICATION SNAPSHOT / WORKFLOW
-- ============================================================================

alter table public.applications
    add column if not exists admission_level text;

alter table public.applications
    add column if not exists applicant_category text;

alter table public.applications
    add column if not exists payment_status text;

alter table public.applications
    add column if not exists submitted_locked_at timestamptz;

alter table public.applications
    add column if not exists decision_status text;

alter table public.applications
    add column if not exists decision_at timestamptz;

alter table public.applications
    add column if not exists decision_by uuid;

update public.applications a
set
    admission_level = coalesce(
        a.admission_level,
        c.admission_level,
        'undergraduate'
    ),
    applicant_category = coalesce(
        a.applicant_category,
        ap.applicant_category,
        'local'
    ),
    payment_status = coalesce(a.payment_status, 'pending'),
    decision_status = coalesce(a.decision_status, 'pending')
from public.admission_cycles c,
     public.applicants ap
where a.admission_cycle_id = c.id
  and a.applicant_id = ap.id
  and (
      a.admission_level is null
      or a.applicant_category is null
      or a.payment_status is null
      or a.decision_status is null
  );

alter table public.applications
    alter column payment_status set default 'pending',
    alter column decision_status set default 'pending';

do $$
begin
    if not exists (
        select 1 from pg_constraint
        where conname = 'applications_level_chk'
          and conrelid = 'public.applications'::regclass
    ) then
        alter table public.applications
        add constraint applications_level_chk
        check (admission_level in ('undergraduate','postgraduate'));
    end if;

    if not exists (
        select 1 from pg_constraint
        where conname = 'applications_category_chk'
          and conrelid = 'public.applications'::regclass
    ) then
        alter table public.applications
        add constraint applications_category_chk
        check (applicant_category in ('local','international'));
    end if;

    if not exists (
        select 1 from pg_constraint
        where conname = 'applications_payment_status_chk'
          and conrelid = 'public.applications'::regclass
    ) then
        alter table public.applications
        add constraint applications_payment_status_chk
        check (payment_status in ('not_required','pending','paid','failed','refunded','waived'));
    end if;

    if not exists (
        select 1 from pg_constraint
        where conname = 'applications_decision_status_chk'
          and conrelid = 'public.applications'::regclass
    ) then
        alter table public.applications
        add constraint applications_decision_status_chk
        check (decision_status in (
            'pending','under_review','qualified','not_qualified',
            'waitlisted','offered','rejected'
        ));
    end if;
end $$;

create index if not exists idx_applications_cycle_status
    on public.applications (admission_cycle_id, status);

create index if not exists idx_applications_category_level
    on public.applications (applicant_category, admission_level);

create index if not exists idx_applications_payment_status
    on public.applications (payment_status);

-- ============================================================================
-- D. APPLICATION FEE RULES
-- One cycle can have different fees for:
--   local undergraduate
--   local postgraduate
--   international undergraduate
--   international postgraduate
-- Optional programme_id permits programme-specific fee overrides.
-- ============================================================================

create table if not exists public.admission_fee_rules (
    id uuid primary key default gen_random_uuid(),
    institution_id uuid not null references public.institutions(id) on delete cascade,
    admission_cycle_id uuid not null references public.admission_cycles(id) on delete cascade,
    programme_id uuid null references public.programmes(id) on delete cascade,

    applicant_category text not null,
    admission_level text not null,

    amount numeric(12,2) not null default 0,
    currency_code text not null default 'GHS',
    is_active boolean not null default true,

    effective_from timestamptz null,
    effective_to timestamptz null,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint admission_fee_rules_category_chk
        check (applicant_category in ('local','international')),

    constraint admission_fee_rules_level_chk
        check (admission_level in ('undergraduate','postgraduate')),

    constraint admission_fee_rules_amount_chk
        check (amount >= 0)
);

create unique index if not exists uq_admission_fee_rules_general
on public.admission_fee_rules (
    admission_cycle_id,
    applicant_category,
    admission_level
)
where programme_id is null;

create unique index if not exists uq_admission_fee_rules_programme
on public.admission_fee_rules (
    admission_cycle_id,
    programme_id,
    applicant_category,
    admission_level
)
where programme_id is not null;

create index if not exists idx_admission_fee_rules_lookup
on public.admission_fee_rules (
    admission_cycle_id,
    applicant_category,
    admission_level,
    is_active
);

-- ============================================================================
-- E. DOCUMENT REQUIREMENTS
-- ============================================================================

create table if not exists public.admission_document_requirements (
    id uuid primary key default gen_random_uuid(),
    institution_id uuid not null references public.institutions(id) on delete cascade,
    admission_cycle_id uuid not null references public.admission_cycles(id) on delete cascade,
    programme_id uuid null references public.programmes(id) on delete cascade,

    applicant_category text not null default 'both',
    admission_level text not null default 'both',

    document_type text not null,
    display_name text not null,
    description text null,

    is_required boolean not null default true,
    requires_verification boolean not null default true,
    accepted_mime_types text[] null,
    max_file_size_bytes bigint null,
    sequence_no integer not null default 100,
    is_active boolean not null default true,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint admission_doc_req_category_chk
        check (applicant_category in ('local','international','both')),

    constraint admission_doc_req_level_chk
        check (admission_level in ('undergraduate','postgraduate','both')),

    constraint admission_doc_req_size_chk
        check (max_file_size_bytes is null or max_file_size_bytes > 0)
);

create index if not exists idx_admission_document_requirements_lookup
on public.admission_document_requirements (
    admission_cycle_id,
    applicant_category,
    admission_level,
    is_active
);

-- ============================================================================
-- F. REVIEW HISTORY
-- Existing applications only contain the latest reviewed_by/reviewed_at.
-- This table preserves the full admissions review history.
-- ============================================================================

create table if not exists public.application_reviews (
    id uuid primary key default gen_random_uuid(),
    institution_id uuid not null references public.institutions(id) on delete cascade,
    application_id uuid not null references public.applications(id) on delete cascade,

    review_stage text not null default 'admissions',
    action text not null,
    old_status text null,
    new_status text null,

    eligibility_status text null,
    recommendation text null,
    comments text null,

    reviewed_by uuid null,
    reviewed_at timestamptz not null default now(),

    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now()
);

create index if not exists idx_application_reviews_application
on public.application_reviews (application_id, reviewed_at desc);

create index if not exists idx_application_reviews_stage
on public.application_reviews (review_stage, reviewed_at desc);

-- ============================================================================
-- G. EXTEND ADMISSION OFFERS
-- ============================================================================

alter table public.admission_offers
    add column if not exists response_status text;

alter table public.admission_offers
    add column if not exists accepted_at timestamptz;

alter table public.admission_offers
    add column if not exists declined_at timestamptz;

alter table public.admission_offers
    add column if not exists student_id uuid;

alter table public.admission_offers
    add column if not exists acceptance_notes text;

update public.admission_offers
set response_status = coalesce(response_status, 'pending')
where response_status is null;

alter table public.admission_offers
    alter column response_status set default 'pending';

do $$
begin
    if not exists (
        select 1 from pg_constraint
        where conname = 'admission_offers_response_status_chk'
          and conrelid = 'public.admission_offers'::regclass
    ) then
        alter table public.admission_offers
        add constraint admission_offers_response_status_chk
        check (response_status in ('pending','accepted','declined','expired'));
    end if;

    if not exists (
        select 1 from pg_constraint
        where conname = 'admission_offers_student_id_fkey'
          and conrelid = 'public.admission_offers'::regclass
    ) then
        alter table public.admission_offers
        add constraint admission_offers_student_id_fkey
        foreign key (student_id)
        references public.students(id)
        on delete set null;
    end if;
end $$;

create index if not exists idx_admission_offers_response
on public.admission_offers (response_status, offered_at desc);

-- ============================================================================
-- H. ATOMIC COUNTERS
-- ============================================================================

create table if not exists public.admission_cycle_counters (
    admission_cycle_id uuid primary key
        references public.admission_cycles(id) on delete cascade,
    last_application_number bigint not null default 0,
    last_offer_number bigint not null default 0,
    updated_at timestamptz not null default now()
);

create table if not exists public.student_number_counters (
    institution_id uuid not null references public.institutions(id) on delete cascade,
    academic_year_id uuid not null references public.academic_years(id) on delete cascade,
    last_number bigint not null default 0,
    updated_at timestamptz not null default now(),
    primary key (institution_id, academic_year_id)
);

-- ============================================================================
-- I. NUMBER GENERATION
-- ============================================================================

create or replace function public.unimis_next_application_number(
    p_admission_cycle_id uuid
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
    v_prefix text;
    v_year text;
    v_next bigint;
begin
    select
        coalesce(nullif(trim(c.application_prefix), ''), 'APP'),
        regexp_replace(coalesce(ay.name, extract(year from current_date)::text), '[^0-9]', '', 'g')
    into v_prefix, v_year
    from public.admission_cycles c
    left join public.academic_years ay on ay.id = c.academic_year_id
    where c.id = p_admission_cycle_id;

    if not found then
        raise exception 'Admission cycle % does not exist.', p_admission_cycle_id;
    end if;

    insert into public.admission_cycle_counters (
        admission_cycle_id,
        last_application_number
    )
    values (p_admission_cycle_id, 1)
    on conflict (admission_cycle_id)
    do update
       set last_application_number =
               public.admission_cycle_counters.last_application_number + 1,
           updated_at = now()
    returning last_application_number into v_next;

    -- Use the first four digits found in the academic-year name.
    v_year := substring(v_year from 1 for 4);
    if v_year is null or length(v_year) < 4 then
        v_year := extract(year from current_date)::text;
    end if;

    return format(
        '%s-%s-%s',
        upper(v_prefix),
        v_year,
        lpad(v_next::text, 6, '0')
    );
end;
$$;

create or replace function public.unimis_next_offer_number(
    p_admission_cycle_id uuid
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
    v_year text;
    v_next bigint;
begin
    select
        substring(
            regexp_replace(
                coalesce(ay.name, extract(year from current_date)::text),
                '[^0-9]',
                '',
                'g'
            ) from 1 for 4
        )
    into v_year
    from public.admission_cycles c
    left join public.academic_years ay on ay.id = c.academic_year_id
    where c.id = p_admission_cycle_id;

    if not found then
        raise exception 'Admission cycle % does not exist.', p_admission_cycle_id;
    end if;

    if v_year is null or length(v_year) < 4 then
        v_year := extract(year from current_date)::text;
    end if;

    insert into public.admission_cycle_counters (
        admission_cycle_id,
        last_offer_number
    )
    values (p_admission_cycle_id, 1)
    on conflict (admission_cycle_id)
    do update
       set last_offer_number =
               public.admission_cycle_counters.last_offer_number + 1,
           updated_at = now()
    returning last_offer_number into v_next;

    return format('OFF-%s-%s', v_year, lpad(v_next::text, 6, '0'));
end;
$$;

create or replace function public.unimis_next_student_number(
    p_institution_id uuid,
    p_academic_year_id uuid
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
    v_code text;
    v_year text;
    v_next bigint;
begin
    select upper(coalesce(nullif(trim(code),''), 'STU'))
    into v_code
    from public.institutions
    where id = p_institution_id;

    if not found then
        raise exception 'Institution % does not exist.', p_institution_id;
    end if;

    select substring(
        regexp_replace(name, '[^0-9]', '', 'g')
        from 1 for 4
    )
    into v_year
    from public.academic_years
    where id = p_academic_year_id;

    if v_year is null or length(v_year) < 4 then
        v_year := extract(year from current_date)::text;
    end if;

    insert into public.student_number_counters (
        institution_id,
        academic_year_id,
        last_number
    )
    values (p_institution_id, p_academic_year_id, 1)
    on conflict (institution_id, academic_year_id)
    do update
       set last_number = public.student_number_counters.last_number + 1,
           updated_at = now()
    returning last_number into v_next;

    return format('%s-%s-%s', v_code, v_year, lpad(v_next::text, 6, '0'));
end;
$$;

-- ============================================================================
-- J. APPLICATION SNAPSHOT / NUMBER TRIGGER
-- Does not interfere with an existing RPC that already supplies a number.
-- ============================================================================

create or replace function public.unimis_prepare_application()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_cycle public.admission_cycles%rowtype;
    v_applicant public.applicants%rowtype;
begin
    select * into v_cycle
    from public.admission_cycles
    where id = new.admission_cycle_id;

    if not found then
        raise exception 'Invalid admission cycle.';
    end if;

    select * into v_applicant
    from public.applicants
    where id = new.applicant_id;

    if not found then
        raise exception 'Invalid applicant.';
    end if;

    if new.institution_id <> v_cycle.institution_id
       or new.institution_id <> v_applicant.institution_id then
        raise exception 'Application institution does not match cycle/applicant.';
    end if;

    new.admission_level :=
        coalesce(new.admission_level,
                 case when v_cycle.admission_level = 'both'
                      then 'undergraduate'
                      else v_cycle.admission_level
                 end);

    new.applicant_category :=
        coalesce(new.applicant_category, v_applicant.applicant_category);

    if v_cycle.admission_level <> 'both'
       and new.admission_level <> v_cycle.admission_level then
        raise exception 'Application level is not permitted for this admission cycle.';
    end if;

    if v_cycle.applicant_scope <> 'both'
       and new.applicant_category <> v_cycle.applicant_scope then
        raise exception 'Applicant category is not permitted for this admission cycle.';
    end if;

    if new.application_number is null
       or btrim(new.application_number) = '' then
        new.application_number :=
            public.unimis_next_application_number(new.admission_cycle_id);
    end if;

    new.payment_status := coalesce(
        new.payment_status,
        case when v_cycle.payment_required then 'pending' else 'not_required' end
    );

    new.decision_status := coalesce(new.decision_status, 'pending');

    return new;
end;
$$;

drop trigger if exists trg_unimis_prepare_application on public.applications;

create trigger trg_unimis_prepare_application
before insert on public.applications
for each row
execute function public.unimis_prepare_application();

-- ============================================================================
-- K. FEE LOOKUP
-- Programme-specific rule wins over general rule.
-- ============================================================================

create or replace function public.unimis_get_application_fee(
    p_application_id uuid
)
returns table (
    fee_rule_id uuid,
    amount numeric,
    currency_code text
)
language sql
stable
security invoker
set search_path = public
as $$
    with app as (
        select
            a.id,
            a.admission_cycle_id,
            a.applicant_category,
            a.admission_level,
            (
                select ac.programme_id
                from public.application_choices ac
                where ac.application_id = a.id
                order by ac.choice_order
                limit 1
            ) as first_programme_id
        from public.applications a
        where a.id = p_application_id
    )
    select
        f.id,
        f.amount,
        f.currency_code
    from app
    join lateral (
        select fr.*
        from public.admission_fee_rules fr
        where fr.admission_cycle_id = app.admission_cycle_id
          and fr.applicant_category = app.applicant_category
          and fr.admission_level = app.admission_level
          and fr.is_active = true
          and (fr.effective_from is null or fr.effective_from <= now())
          and (fr.effective_to is null or fr.effective_to >= now())
          and (
              fr.programme_id is null
              or fr.programme_id = app.first_programme_id
          )
        order by
            case when fr.programme_id = app.first_programme_id then 0 else 1 end,
            fr.created_at desc
        limit 1
    ) f on true;
$$;

-- ============================================================================
-- L. PAYMENT CONFIRMATION
-- Existing table statuses may already be used by the frontend/provider.
-- Treat paid/success/successful/verified/completed as confirmed.
-- ============================================================================

create or replace function public.unimis_application_payment_confirmed(
    p_application_id uuid
)
returns boolean
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
    v_required boolean;
    v_expected numeric;
    v_currency text;
    v_paid numeric;
begin
    select c.payment_required
    into v_required
    from public.applications a
    join public.admission_cycles c on c.id = a.admission_cycle_id
    where a.id = p_application_id;

    if not found then
        raise exception 'Application % does not exist.', p_application_id;
    end if;

    if v_required = false then
        return true;
    end if;

    select f.amount, f.currency_code
    into v_expected, v_currency
    from public.unimis_get_application_fee(p_application_id) f
    limit 1;

    if v_expected is null then
        return false;
    end if;

    select coalesce(sum(p.amount), 0)
    into v_paid
    from public.admission_application_payments p
    where p.application_id = p_application_id
      and upper(p.currency) = upper(v_currency)
      and lower(p.status) in (
          'paid','success','successful','verified','completed'
      );

    return v_paid >= v_expected;
end;
$$;

-- ============================================================================
-- M. REQUIRED DOCUMENT CHECK
-- A requirement can be general or programme-specific.
-- Uploaded document types are matched against application_documents.document_type.
-- ============================================================================

create or replace function public.unimis_missing_application_documents(
    p_application_id uuid
)
returns table (
    requirement_id uuid,
    document_type text,
    display_name text
)
language sql
stable
security invoker
set search_path = public
as $$
    with app as (
        select
            a.id,
            a.institution_id,
            a.admission_cycle_id,
            a.applicant_category,
            a.admission_level,
            (
                select ac.programme_id
                from public.application_choices ac
                where ac.application_id = a.id
                order by ac.choice_order
                limit 1
            ) as first_programme_id
        from public.applications a
        where a.id = p_application_id
    )
    select
        r.id,
        r.document_type,
        r.display_name
    from app
    join public.admission_document_requirements r
      on r.admission_cycle_id = app.admission_cycle_id
     and r.is_active = true
     and r.is_required = true
     and r.applicant_category in ('both', app.applicant_category)
     and r.admission_level in ('both', app.admission_level)
     and (r.programme_id is null or r.programme_id = app.first_programme_id)
    where not exists (
        select 1
        from public.application_documents d
        where d.application_id = app.id
          and lower(d.document_type) = lower(r.document_type)
    )
    order by r.sequence_no, r.display_name;
$$;

-- ============================================================================
-- N. SUBMIT APPLICATION
-- This is SECURITY INVOKER intentionally: existing RLS remains authoritative.
-- ============================================================================

create or replace function public.unimis_submit_application(
    p_application_id uuid
)
returns public.applications
language plpgsql
security invoker
set search_path = public
as $$
declare
    v_app public.applications%rowtype;
    v_cycle public.admission_cycles%rowtype;
    v_choice_count integer;
    v_missing integer;
    v_paid boolean;
begin
    select * into v_app
    from public.applications
    where id = p_application_id
    for update;

    if not found then
        raise exception 'Application not found.';
    end if;

    if lower(v_app.status) not in ('draft','incomplete','returned') then
        raise exception 'Application cannot be submitted from status "%".', v_app.status;
    end if;

    select * into v_cycle
    from public.admission_cycles
    where id = v_app.admission_cycle_id;

    if v_cycle.status not in ('open','active') then
        raise exception 'Admission cycle is not open.';
    end if;

    if v_cycle.opens_at is not null and now() < v_cycle.opens_at then
        raise exception 'Admission cycle has not opened.';
    end if;

    if v_cycle.closes_at is not null and now() > v_cycle.closes_at then
        raise exception 'Admission cycle has closed.';
    end if;

    select count(*)
    into v_choice_count
    from public.application_choices
    where application_id = p_application_id;

    if v_choice_count < 1 then
        raise exception 'At least one programme choice is required.';
    end if;

    if v_choice_count > v_cycle.max_programme_choices then
        raise exception 'Maximum programme choices allowed: %.',
            v_cycle.max_programme_choices;
    end if;

    select count(*)
    into v_missing
    from public.unimis_missing_application_documents(p_application_id);

    if v_missing > 0 then
        raise exception '% required application document(s) are missing.', v_missing;
    end if;

    v_paid := public.unimis_application_payment_confirmed(p_application_id);

    if not v_paid then
        raise exception 'Application fee has not been fully verified.';
    end if;

    update public.applications
    set
        status = 'submitted',
        payment_status =
            case when v_cycle.payment_required then 'paid' else 'not_required' end,
        submitted_at = coalesce(submitted_at, now()),
        submitted_locked_at = now(),
        updated_at = now()
    where id = p_application_id
    returning * into v_app;

    return v_app;
end;
$$;

-- ============================================================================
-- O. RECORD ADMISSIONS DECISION
-- Intended for trusted staff workflows. Existing RLS still governs application
-- access because the function is SECURITY INVOKER.
-- ============================================================================

create or replace function public.unimis_record_application_decision(
    p_application_id uuid,
    p_decision text,
    p_comments text default null
)
returns public.applications
language plpgsql
security invoker
set search_path = public
as $$
declare
    v_app public.applications%rowtype;
    v_old_status text;
begin
    if p_decision not in (
        'under_review','qualified','not_qualified',
        'waitlisted','offered','rejected'
    ) then
        raise exception 'Unsupported admissions decision: %', p_decision;
    end if;

    select * into v_app
    from public.applications
    where id = p_application_id
    for update;

    if not found then
        raise exception 'Application not found.';
    end if;

    v_old_status := v_app.decision_status;

    update public.applications
    set
        decision_status = p_decision,
        decision_at = now(),
        decision_by = auth.uid(),
        reviewed_at = now(),
        reviewed_by = auth.uid(),
        updated_at = now()
    where id = p_application_id
    returning * into v_app;

    insert into public.application_reviews (
        institution_id,
        application_id,
        review_stage,
        action,
        old_status,
        new_status,
        recommendation,
        comments,
        reviewed_by
    )
    values (
        v_app.institution_id,
        v_app.id,
        'admissions',
        'decision',
        v_old_status,
        p_decision,
        p_decision,
        p_comments,
        auth.uid()
    );

    return v_app;
end;
$$;

-- ============================================================================
-- P. CREATE OFFER
-- Creates one offer and marks application decision = offered.
-- ============================================================================

create or replace function public.unimis_create_admission_offer(
    p_application_id uuid,
    p_programme_id uuid,
    p_offer_type text default 'regular',
    p_conditions text default null,
    p_expires_at timestamptz default null
)
returns public.admission_offers
language plpgsql
security invoker
set search_path = public
as $$
declare
    v_app public.applications%rowtype;
    v_offer public.admission_offers%rowtype;
    v_offer_number text;
begin
    select * into v_app
    from public.applications
    where id = p_application_id
    for update;

    if not found then
        raise exception 'Application not found.';
    end if;

    if not exists (
        select 1
        from public.application_choices ac
        where ac.application_id = p_application_id
          and ac.programme_id = p_programme_id
    ) then
        raise exception 'Programme is not one of the applicant''s choices.';
    end if;

    v_offer_number :=
        public.unimis_next_offer_number(v_app.admission_cycle_id);

    insert into public.admission_offers (
        institution_id,
        application_id,
        programme_id,
        offer_number,
        offer_type,
        decision,
        offered_at,
        expires_at,
        conditions,
        approved_by,
        response_status
    )
    values (
        v_app.institution_id,
        v_app.id,
        p_programme_id,
        v_offer_number,
        p_offer_type,
        'offered',
        now(),
        p_expires_at,
        p_conditions,
        auth.uid(),
        'pending'
    )
    returning * into v_offer;

    update public.applications
    set
        decision_status = 'offered',
        decision_at = now(),
        decision_by = auth.uid(),
        reviewed_at = now(),
        reviewed_by = auth.uid(),
        updated_at = now()
    where id = p_application_id;

    insert into public.application_reviews (
        institution_id,
        application_id,
        review_stage,
        action,
        old_status,
        new_status,
        recommendation,
        comments,
        reviewed_by,
        metadata
    )
    values (
        v_app.institution_id,
        v_app.id,
        'offer',
        'offer_created',
        v_app.decision_status,
        'offered',
        'offered',
        p_conditions,
        auth.uid(),
        jsonb_build_object(
            'offer_id', v_offer.id,
            'programme_id', p_programme_id,
            'offer_number', v_offer.offer_number
        )
    );

    return v_offer;
end;
$$;

-- ============================================================================
-- Q. RESPOND TO OFFER
-- SECURITY INVOKER: applicant ownership will be controlled by RLS after audit.
-- ============================================================================

create or replace function public.unimis_respond_to_offer(
    p_offer_id uuid,
    p_response text,
    p_notes text default null
)
returns public.admission_offers
language plpgsql
security invoker
set search_path = public
as $$
declare
    v_offer public.admission_offers%rowtype;
begin
    if p_response not in ('accepted','declined') then
        raise exception 'Response must be accepted or declined.';
    end if;

    select * into v_offer
    from public.admission_offers
    where id = p_offer_id
    for update;

    if not found then
        raise exception 'Admission offer not found.';
    end if;

    if v_offer.response_status <> 'pending' then
        raise exception 'This offer has already been responded to.';
    end if;

    if v_offer.expires_at is not null and now() > v_offer.expires_at then
        update public.admission_offers
        set response_status = 'expired',
            responded_at = now(),
            updated_at = now()
        where id = p_offer_id;

        raise exception 'Admission offer has expired.';
    end if;

    update public.admission_offers
    set
        response_status = p_response,
        responded_at = now(),
        accepted_at = case when p_response = 'accepted' then now() else null end,
        declined_at = case when p_response = 'declined' then now() else null end,
        acceptance_notes = p_notes,
        updated_at = now()
    where id = p_offer_id
    returning * into v_offer;

    return v_offer;
end;
$$;

-- ============================================================================
-- R. CONVERT ACCEPTED OFFER TO STUDENT
--
-- This function does NOT create auth.users. That should be handled by a trusted
-- Edge Function/Admin API. p_user_id can be supplied later or left null.
--
-- Access is restricted to service_role because it creates official student
-- records.
-- ============================================================================

create or replace function public.unimis_convert_offer_to_student(
    p_offer_id uuid,
    p_student_number text default null,
    p_user_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_offer public.admission_offers%rowtype;
    v_app public.applications%rowtype;
    v_applicant public.applicants%rowtype;
    v_cycle public.admission_cycles%rowtype;
    v_student_id uuid;
    v_student_number text;
    v_cohort_year integer;
begin
    select * into v_offer
    from public.admission_offers
    where id = p_offer_id
    for update;

    if not found then
        raise exception 'Admission offer not found.';
    end if;

    if v_offer.response_status <> 'accepted' then
        raise exception 'Only an accepted admission offer can be converted.';
    end if;

    -- Idempotent: return already-created student.
    if v_offer.student_id is not null then
        return v_offer.student_id;
    end if;

    select * into v_app
    from public.applications
    where id = v_offer.application_id;

    select * into v_applicant
    from public.applicants
    where id = v_app.applicant_id;

    select * into v_cycle
    from public.admission_cycles
    where id = v_app.admission_cycle_id;

    select s.id
    into v_student_id
    from public.students s
    where s.application_id = v_app.id
    limit 1;

    if v_student_id is null then
        v_student_number := coalesce(
            nullif(trim(p_student_number), ''),
            public.unimis_next_student_number(
                v_app.institution_id,
                v_cycle.academic_year_id
            )
        );

        if exists (
            select 1
            from public.students s
            where s.student_number = v_student_number
        ) then
            raise exception 'Student number % already exists.', v_student_number;
        end if;

        insert into public.students (
            institution_id,
            user_id,
            applicant_id,
            application_id,
            student_number,
            first_name,
            middle_name,
            last_name,
            date_of_birth,
            gender,
            email,
            phone,
            nationality,
            address,
            city,
            region,
            admission_date,
            student_type,
            status
        )
        values (
            v_app.institution_id,
            p_user_id,
            v_applicant.id,
            v_app.id,
            v_student_number,
            v_applicant.first_name,
            v_applicant.middle_name,
            v_applicant.last_name,
            v_applicant.date_of_birth,
            v_applicant.gender,
            v_applicant.email,
            v_applicant.phone,
            v_applicant.nationality,
            v_applicant.address,
            v_applicant.city,
            v_applicant.region,
            current_date,
            coalesce(v_app.entry_type, 'regular'),
            'active'
        )
        returning id into v_student_id;
    else
        if p_user_id is not null then
            update public.students
            set user_id = coalesce(user_id, p_user_id),
                updated_at = now()
            where id = v_student_id;
        end if;
    end if;

    begin
        select substring(
            regexp_replace(ay.name, '[^0-9]', '', 'g')
            from 1 for 4
        )::integer
        into v_cohort_year
        from public.academic_years ay
        where ay.id = v_cycle.academic_year_id;
    exception
        when others then
            v_cohort_year := extract(year from current_date)::integer;
    end;

    if v_cohort_year is null then
        v_cohort_year := extract(year from current_date)::integer;
    end if;

    if not exists (
        select 1
        from public.student_programme_enrolments spe
        where spe.student_id = v_student_id
          and spe.programme_id = v_offer.programme_id
          and spe.is_primary = true
    ) then
        insert into public.student_programme_enrolments (
            institution_id,
            student_id,
            programme_id,
            admission_academic_year_id,
            cohort_year,
            current_level,
            enrolment_status,
            start_date,
            is_primary
        )
        values (
            v_app.institution_id,
            v_student_id,
            v_offer.programme_id,
            v_cycle.academic_year_id,
            v_cohort_year,
            100,
            'active',
            current_date,
            true
        );
    end if;

    update public.admission_offers
    set student_id = v_student_id,
        updated_at = now()
    where id = p_offer_id;

    return v_student_id;
end;
$$;

revoke all on function public.unimis_convert_offer_to_student(uuid,text,uuid)
from public, anon, authenticated;

grant execute on function public.unimis_convert_offer_to_student(uuid,text,uuid)
to service_role;

-- ============================================================================
-- S. PAYMENT STATUS SYNC TRIGGER
-- Keeps applications.payment_status synchronized after payment writes.
-- ============================================================================

create or replace function public.unimis_sync_application_payment_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_application_id uuid;
    v_confirmed boolean;
begin
    v_application_id :=
        case
            when TG_OP = 'DELETE' then old.application_id
            else new.application_id
        end;

    begin
        v_confirmed :=
            public.unimis_application_payment_confirmed(v_application_id);

        update public.applications
        set
            payment_status =
                case
                    when v_confirmed then 'paid'
                    else 'pending'
                end,
            updated_at = now()
        where id = v_application_id
          and payment_status <> 'not_required';
    exception
        when others then
            -- Payment writes should not fail because no fee rule has yet been
            -- configured. Leave status unchanged and allow transaction.
            null;
    end;

    if TG_OP = 'DELETE' then
        return old;
    else
        return new;
    end if;
end;
$$;

drop trigger if exists trg_unimis_sync_application_payment_status
on public.admission_application_payments;

create trigger trg_unimis_sync_application_payment_status
after insert or update or delete
on public.admission_application_payments
for each row
execute function public.unimis_sync_application_payment_status();

-- ============================================================================
-- T. UPDATED_AT TRIGGER FOR NEW CONFIG TABLES
-- ============================================================================

create or replace function public.unimis_touch_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists trg_admission_fee_rules_updated_at
on public.admission_fee_rules;
create trigger trg_admission_fee_rules_updated_at
before update on public.admission_fee_rules
for each row execute function public.unimis_touch_updated_at();

drop trigger if exists trg_admission_document_requirements_updated_at
on public.admission_document_requirements;
create trigger trg_admission_document_requirements_updated_at
before update on public.admission_document_requirements
for each row execute function public.unimis_touch_updated_at();

-- ============================================================================
-- U. COMMENTS
-- ============================================================================

comment on table public.admission_fee_rules is
'Configurable application fee rules by cycle, local/international category and undergraduate/postgraduate level.';

comment on table public.admission_document_requirements is
'Configurable document requirements for admissions, optionally programme-specific.';

comment on table public.application_reviews is
'Immutable-style admissions review/decision history for each application.';

comment on function public.unimis_convert_offer_to_student(uuid,text,uuid) is
'Converts an accepted admission offer into the existing students and student_programme_enrolments structures. Does not create auth.users.';

commit;

-- ============================================================================
-- VERIFICATION QUERIES
-- Run separately after migration.
-- ============================================================================

-- 1. Confirm new columns on admission_cycles:
-- select column_name, data_type, column_default
-- from information_schema.columns
-- where table_schema='public' and table_name='admission_cycles'
-- order by ordinal_position;

-- 2. Confirm new tables:
-- select table_name
-- from information_schema.tables
-- where table_schema='public'
--   and table_name in (
--      'admission_fee_rules',
--      'admission_document_requirements',
--      'application_reviews',
--      'admission_cycle_counters',
--      'student_number_counters'
--   )
-- order by table_name;

-- 3. Confirm functions:
-- select p.proname, pg_get_function_identity_arguments(p.oid)
-- from pg_proc p
-- join pg_namespace n on n.oid=p.pronamespace
-- where n.nspname='public'
--   and p.proname like 'unimis_%admission%'
--    or (n.nspname='public' and p.proname like 'unimis_%application%')
-- order by p.proname;

-- 4. Inspect cycles before configuring them:
-- select
--   id, name, admission_level, applicant_scope,
--   max_programme_choices, payment_required, status
-- from public.admission_cycles
-- order by created_at desc;

-- 5. Example fee configuration (EDIT IDS before use):
-- insert into public.admission_fee_rules (
--   institution_id, admission_cycle_id,
--   applicant_category, admission_level, amount, currency_code
-- ) values
--   ('INSTITUTION_UUID','CYCLE_UUID','local','undergraduate',250,'GHS'),
--   ('INSTITUTION_UUID','CYCLE_UUID','international','undergraduate',100,'USD');

-- 6. Example document requirement (EDIT IDS before use):
-- insert into public.admission_document_requirements (
--   institution_id, admission_cycle_id,
--   applicant_category, admission_level,
--   document_type, display_name, is_required, sequence_no
-- ) values
--   ('INSTITUTION_UUID','CYCLE_UUID','both','undergraduate',
--    'passport_photo','Passport Photograph',true,10);

-- 7. Check latest applications:
-- select
--   application_number, applicant_category, admission_level,
--   payment_status, status, decision_status
-- from public.applications
-- order by created_at desc
-- limit 20;
