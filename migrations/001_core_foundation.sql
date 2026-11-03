-- ============================================================
-- UNIVERSAL EDUCATION MIS
-- MODULE 01A: CORE FOUNDATION
-- ============================================================

create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.institutions (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  short_name text,
  code text not null unique,
  institution_type text not null
    check (institution_type in ('jhs','shs','university','college','technical','vocational','other')),
  status text not null default 'active'
    check (status in ('active','inactive','suspended','archived')),
  email text,
  phone text,
  website text,
  country text default 'Ghana',
  region text,
  city text,
  address text,
  currency_code text not null default 'GHS',
  timezone text not null default 'Africa/Accra',
  logo_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  first_name text,
  middle_name text,
  last_name text,
  display_name text,
  phone text,
  avatar_url text,
  status text not null default 'active'
    check (status in ('active','inactive','suspended')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.roles (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid references public.institutions(id) on delete cascade,
  name text not null,
  code text not null,
  description text,
  is_system_role boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (institution_id, code)
);

create table if not exists public.permissions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  module text not null,
  description text,
  created_at timestamptz not null default now()
);

create table if not exists public.role_permissions (
  role_id uuid not null references public.roles(id) on delete cascade,
  permission_id uuid not null references public.permissions(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (role_id, permission_id)
);

create table if not exists public.institution_users (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role_id uuid references public.roles(id) on delete set null,
  staff_number text,
  student_number text,
  status text not null default 'active'
    check (status in ('active','inactive','suspended','pending')),
  is_primary boolean not null default false,
  joined_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (institution_id, user_id)
);

create table if not exists public.institution_features (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  feature_code text not null,
  enabled boolean not null default true,
  settings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (institution_id, feature_code)
);

create table if not exists public.institution_settings (
  institution_id uuid primary key references public.institutions(id) on delete cascade,
  primary_color text,
  secondary_color text,
  login_title text,
  portal_name text,
  custom_domain text,
  subdomain text,
  academic_settings jsonb not null default '{}'::jsonb,
  branding_settings jsonb not null default '{}'::jsonb,
  communication_settings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_institutions_type on public.institutions(institution_type);
create index if not exists idx_institution_users_institution on public.institution_users(institution_id);
create index if not exists idx_institution_users_user on public.institution_users(user_id);
create index if not exists idx_roles_institution on public.roles(institution_id);
create index if not exists idx_features_institution on public.institution_features(institution_id);

drop trigger if exists trg_institutions_updated_at on public.institutions;
create trigger trg_institutions_updated_at before update on public.institutions
for each row execute function public.set_updated_at();

drop trigger if exists trg_profiles_updated_at on public.profiles;
create trigger trg_profiles_updated_at before update on public.profiles
for each row execute function public.set_updated_at();

drop trigger if exists trg_roles_updated_at on public.roles;
create trigger trg_roles_updated_at before update on public.roles
for each row execute function public.set_updated_at();

drop trigger if exists trg_institution_users_updated_at on public.institution_users;
create trigger trg_institution_users_updated_at before update on public.institution_users
for each row execute function public.set_updated_at();

drop trigger if exists trg_institution_features_updated_at on public.institution_features;
create trigger trg_institution_features_updated_at before update on public.institution_features
for each row execute function public.set_updated_at();

drop trigger if exists trg_institution_settings_updated_at on public.institution_settings;
create trigger trg_institution_settings_updated_at before update on public.institution_settings
for each row execute function public.set_updated_at();

-- END MODULE 01A
