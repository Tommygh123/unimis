-- UniMIS Student Lifecycle Phase — settings + numbering foundation
begin;

create table if not exists public.student_number_sequences (
  institution_id uuid not null,
  academic_year integer not null,
  last_number bigint not null default 0,
  updated_at timestamptz not null default now(),
  primary key (institution_id, academic_year)
);

create table if not exists public.student_conversion_history (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  application_id uuid not null,
  applicant_id uuid,
  student_id uuid,
  offer_id uuid,
  action text not null default 'converted',
  student_number text,
  converted_by uuid,
  converted_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists idx_student_conversion_history_application
  on public.student_conversion_history(application_id, converted_at desc);
create index if not exists idx_student_conversion_history_student
  on public.student_conversion_history(student_id, converted_at desc);

insert into public.institution_settings(
  institution_id, academic_settings, branding_settings, communication_settings
)
select i.id,
  jsonb_build_object(
    'student_numbering', jsonb_build_object(
      'prefix', coalesce(i.short_name,'STU'),
      'include_year', true,
      'digits', 5,
      'separator', '/'
    ),
    'student_conversion', jsonb_build_object(
      'auto_create_period_registration', true,
      'auto_generate_initial_invoice', false,
      'auto_assign_student_role', true,
      'initial_level', 100
    ),
    'registration', jsonb_build_object(
      'require_fee_clearance', false,
      'allow_late_registration', false
    )
  ),
  '{}'::jsonb,
  '{}'::jsonb
from public.institutions i
where not exists (
  select 1 from public.institution_settings s where s.institution_id=i.id
);

update public.institution_settings
set academic_settings =
  coalesce(academic_settings,'{}'::jsonb)
  || jsonb_build_object(
    'student_numbering',
    coalesce(academic_settings->'student_numbering',
      jsonb_build_object('prefix','STU','include_year',true,'digits',5,'separator','/')),
    'student_conversion',
    coalesce(academic_settings->'student_conversion',
      jsonb_build_object('auto_create_period_registration',true,'auto_generate_initial_invoice',false,'auto_assign_student_role',true,'initial_level',100)),
    'registration',
    coalesce(academic_settings->'registration',
      jsonb_build_object('require_fee_clearance',false,'allow_late_registration',false))
  );

alter table public.student_number_sequences enable row level security;
alter table public.student_conversion_history enable row level security;

drop policy if exists "Settings managers view student number sequences" on public.student_number_sequences;
create policy "Settings managers view student number sequences"
on public.student_number_sequences for select to authenticated
using (
  public.has_permission(institution_id,'settings.view')
  or public.has_permission(institution_id,'settings.manage')
  or public.has_permission(institution_id,'students.manage')
);

drop policy if exists "Student managers view conversion history" on public.student_conversion_history;
create policy "Student managers view conversion history"
on public.student_conversion_history for select to authenticated
using (
  public.has_permission(institution_id,'students.view')
  or public.has_permission(institution_id,'students.manage')
  or public.has_permission(institution_id,'admissions.manage')
);

create or replace function public.unimis_student_lifecycle_settings(p_institution_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_settings jsonb;
begin
  if not (
    public.has_permission(p_institution_id,'settings.view')
    or public.has_permission(p_institution_id,'settings.manage')
    or public.has_permission(p_institution_id,'students.manage')
  ) then
    raise exception 'You do not have permission to view student lifecycle settings';
  end if;

  select coalesce(academic_settings,'{}'::jsonb)
  into v_settings
  from public.institution_settings
  where institution_id=p_institution_id;

  return coalesce(v_settings,'{}'::jsonb);
end $$;

create or replace function public.unimis_update_student_lifecycle_settings(
  p_institution_id uuid,
  p_settings jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_result jsonb;
begin
  if not public.has_permission(p_institution_id,'settings.manage') then
    raise exception 'You do not have permission to change institution settings';
  end if;

  insert into public.institution_settings(institution_id,academic_settings)
  values(p_institution_id,coalesce(p_settings,'{}'::jsonb))
  on conflict(institution_id) do update
    set academic_settings=coalesce(public.institution_settings.academic_settings,'{}'::jsonb)
      || coalesce(excluded.academic_settings,'{}'::jsonb),
        updated_at=now()
  returning academic_settings into v_result;

  return v_result;
end $$;

grant execute on function public.unimis_student_lifecycle_settings(uuid) to authenticated;
grant execute on function public.unimis_update_student_lifecycle_settings(uuid,jsonb) to authenticated;

commit;
