-- ============================================================
-- UNIMIS MODULE 03
-- ADMISSIONS MANAGEMENT
-- 005_admissions.sql
-- Run AFTER Module 02
-- ============================================================

-- ============================================================
-- SECTION 03A — ADMISSION CYCLES
-- ============================================================

create table if not exists public.admission_cycles (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  academic_year_id uuid not null references public.academic_years(id) on delete cascade,
  name text not null,
  application_prefix text not null default 'APP',
  opens_at timestamptz,
  closes_at timestamptz,
  status text not null default 'draft'
    check (status in ('draft','open','closed','archived')),
  settings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (institution_id, name),
  check (closes_at is null or opens_at is null or closes_at > opens_at)
);

-- ============================================================
-- SECTION 03B — APPLICANTS
-- Applicant does NOT need an auth account initially.
-- ============================================================

create table if not exists public.applicants (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,

  first_name text not null,
  middle_name text,
  last_name text not null,
  date_of_birth date,
  gender text check (gender in ('male','female','other','prefer_not_to_say')),

  email text,
  phone text,
  nationality text default 'Ghanaian',
  country_of_residence text default 'Ghana',

  address text,
  city text,
  region text,

  emergency_contact_name text,
  emergency_contact_phone text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (institution_id, user_id)
);

-- ============================================================
-- SECTION 03C — APPLICATIONS
-- ============================================================

create table if not exists public.applications (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  admission_cycle_id uuid not null references public.admission_cycles(id) on delete cascade,
  applicant_id uuid not null references public.applicants(id) on delete cascade,

  application_number text not null,

  entry_type text not null default 'regular'
    check (entry_type in ('regular','mature','transfer','international','other')),

  status text not null default 'draft'
    check (
      status in (
        'draft',
        'submitted',
        'under_review',
        'shortlisted',
        'offered',
        'rejected',
        'waitlisted',
        'accepted',
        'declined',
        'cancelled'
      )
    ),

  submitted_at timestamptz,
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null,

  notes text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (institution_id, application_number),
  unique (admission_cycle_id, applicant_id)
);

-- ============================================================
-- SECTION 03D — PROGRAMME CHOICES
-- ============================================================

create table if not exists public.application_choices (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  application_id uuid not null references public.applications(id) on delete cascade,
  programme_id uuid not null references public.programmes(id) on delete restrict,

  choice_order integer not null check (choice_order > 0),
  status text not null default 'pending'
    check (status in ('pending','eligible','ineligible','selected','not_selected')),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (application_id, choice_order),
  unique (application_id, programme_id)
);

-- ============================================================
-- SECTION 03E — APPLICANT QUALIFICATIONS
-- Generic enough for WASSCE, diploma, degree, etc.
-- ============================================================

create table if not exists public.applicant_qualifications (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  applicant_id uuid not null references public.applicants(id) on delete cascade,

  qualification_type text not null,
  institution_name text,
  examining_body text,
  index_number text,
  completion_year integer,
  overall_result text,
  details jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ============================================================
-- SECTION 03F — APPLICATION DOCUMENTS
-- Actual files later live in Supabase Storage.
-- ============================================================

create table if not exists public.application_documents (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  application_id uuid not null references public.applications(id) on delete cascade,

  document_type text not null,
  file_name text not null,
  storage_path text not null,
  mime_type text,
  file_size_bytes bigint check (file_size_bytes is null or file_size_bytes >= 0),

  verification_status text not null default 'pending'
    check (verification_status in ('pending','verified','rejected')),

  verified_by uuid references auth.users(id) on delete set null,
  verified_at timestamptz,
  notes text,

  created_at timestamptz not null default now()
);

-- ============================================================
-- SECTION 03G — ADMISSION OFFERS
-- ============================================================

create table if not exists public.admission_offers (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  application_id uuid not null references public.applications(id) on delete cascade,
  programme_id uuid not null references public.programmes(id) on delete restrict,

  offer_number text not null,
  offer_type text not null default 'regular'
    check (offer_type in ('regular','conditional','provisional')),

  decision text not null default 'offered'
    check (decision in ('offered','accepted','declined','withdrawn','expired')),

  offered_at timestamptz not null default now(),
  expires_at timestamptz,
  responded_at timestamptz,

  conditions text,
  admission_letter_path text,

  approved_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (institution_id, offer_number),
  unique (application_id)
);

-- ============================================================
-- SECTION 03H — APPLICATION NUMBER GENERATOR
-- ============================================================

create sequence if not exists public.application_number_seq start 1001;

create or replace function public.generate_application_number()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  prefix text;
  yr text;
  seq_no bigint;
begin
  if new.application_number is null or btrim(new.application_number) = '' then

    select coalesce(ac.application_prefix, 'APP')
      into prefix
    from public.admission_cycles ac
    where ac.id = new.admission_cycle_id
      and ac.institution_id = new.institution_id;

    if prefix is null then
      raise exception 'Invalid admission cycle for institution';
    end if;

    yr := to_char(current_date, 'YYYY');
    seq_no := nextval('public.application_number_seq');

    new.application_number :=
      upper(prefix) || '-' || yr || '-' || lpad(seq_no::text, 6, '0');
  end if;

  return new;
end;
$$;

revoke all on function public.generate_application_number() from public;

drop trigger if exists trg_generate_application_number on public.applications;

create trigger trg_generate_application_number
before insert on public.applications
for each row
execute function public.generate_application_number();

-- ============================================================
-- SECTION 03I — INDEXES
-- ============================================================

create index if not exists idx_admission_cycles_institution
  on public.admission_cycles(institution_id);

create index if not exists idx_applicants_institution
  on public.applicants(institution_id);

create index if not exists idx_applicants_email
  on public.applicants(institution_id, email);

create index if not exists idx_applications_institution
  on public.applications(institution_id);

create index if not exists idx_applications_cycle
  on public.applications(admission_cycle_id);

create index if not exists idx_applications_applicant
  on public.applications(applicant_id);

create index if not exists idx_applications_status
  on public.applications(institution_id, status);

create index if not exists idx_application_choices_application
  on public.application_choices(application_id);

create index if not exists idx_qualifications_applicant
  on public.applicant_qualifications(applicant_id);

create index if not exists idx_application_documents_application
  on public.application_documents(application_id);

create index if not exists idx_admission_offers_application
  on public.admission_offers(application_id);

-- ============================================================
-- SECTION 03J — UPDATED_AT TRIGGERS
-- ============================================================

do $$
declare
  t text;
begin
  foreach t in array array[
    'admission_cycles',
    'applicants',
    'applications',
    'application_choices',
    'applicant_qualifications',
    'admission_offers'
  ]
  loop
    execute format(
      'drop trigger if exists trg_%I_updated_at on public.%I',
      t, t
    );

    execute format(
      'create trigger trg_%I_updated_at
       before update on public.%I
       for each row execute function public.set_updated_at()',
      t, t
    );
  end loop;
end $$;

-- ============================================================
-- SECTION 03K — ENABLE RLS
-- ============================================================

alter table public.admission_cycles enable row level security;
alter table public.applicants enable row level security;
alter table public.applications enable row level security;
alter table public.application_choices enable row level security;
alter table public.applicant_qualifications enable row level security;
alter table public.application_documents enable row level security;
alter table public.admission_offers enable row level security;

-- ============================================================
-- SECTION 03L — STAFF ADMISSIONS RLS
-- Applicant self-service policies will be added with the
-- applicant portal/auth workflow, rather than opening tables now.
-- ============================================================

do $$
declare
  t text;
begin
  foreach t in array array[
    'admission_cycles',
    'applicants',
    'applications',
    'application_choices',
    'applicant_qualifications',
    'application_documents',
    'admission_offers'
  ]
  loop
    execute format(
      'drop policy if exists "Admissions viewers can view %s" on public.%I',
      t, t
    );

    execute format(
      'create policy "Admissions viewers can view %s"
       on public.%I
       for select
       to authenticated
       using (
         public.has_permission(institution_id, ''admissions.view'')
         or public.has_permission(institution_id, ''admissions.manage'')
       )',
      t, t
    );

    execute format(
      'drop policy if exists "Admissions managers can manage %s" on public.%I',
      t, t
    );

    execute format(
      'create policy "Admissions managers can manage %s"
       on public.%I
       for all
       to authenticated
       using (
         public.has_permission(institution_id, ''admissions.manage'')
       )
       with check (
         public.has_permission(institution_id, ''admissions.manage'')
       )',
      t, t
    );
  end loop;
end $$;

-- ============================================================
-- SECTION 03M — DEMO 2026/2027 ADMISSION CYCLE
-- ============================================================

insert into public.admission_cycles (
  institution_id,
  academic_year_id,
  name,
  application_prefix,
  opens_at,
  closes_at,
  status
)
select
  i.id,
  ay.id,
  '2026/2027 Undergraduate Admissions',
  'UDU',
  timestamptz '2026-08-01 00:00:00+00',
  timestamptz '2027-03-31 23:59:59+00',
  'open'
from public.institutions i
join public.academic_years ay
  on ay.institution_id = i.id
 and ay.name = '2026/2027'
where i.code = 'UNIMIS-DEMO-UNIV'
on conflict (institution_id, name)
do update set
  application_prefix = excluded.application_prefix,
  opens_at = excluded.opens_at,
  closes_at = excluded.closes_at,
  status = excluded.status,
  updated_at = now();

-- ============================================================
-- SECTION 03N — VERIFICATION
-- ============================================================

select
  ac.name as admission_cycle,
  ac.status,
  i.name as institution,
  ay.name as academic_year
from public.admission_cycles ac
join public.institutions i on i.id = ac.institution_id
join public.academic_years ay on ay.id = ac.academic_year_id
where i.code = 'UNIMIS-DEMO-UNIV';

-- ============================================================
-- END UNIMIS MODULE 03 — ADMISSIONS MANAGEMENT
-- ============================================================
