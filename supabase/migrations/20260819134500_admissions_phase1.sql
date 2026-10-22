-- ============================================================
-- UniMIS Admissions Phase 1
-- Dashboard + Admission Cycles + Applicants + Applications
-- ============================================================

grant usage on schema public to authenticated;

grant select, insert, update
on table public.admission_cycles
to authenticated;

grant select, insert, update
on table public.applicants
to authenticated;

grant select, insert, update
on table public.applications
to authenticated;

grant select, insert, update
on table public.application_choices
to authenticated;

grant select
on table public.programmes,
         public.academic_years
to authenticated;


-- ------------------------------------------------------------
-- RLS
-- ------------------------------------------------------------

alter table public.admission_cycles enable row level security;
alter table public.applicants enable row level security;
alter table public.applications enable row level security;
alter table public.application_choices enable row level security;

drop policy if exists "Admissions viewers can view admission cycles"
on public.admission_cycles;

create policy "Admissions viewers can view admission cycles"
on public.admission_cycles
for select
to authenticated
using (
  public.has_permission(institution_id, 'admissions.view')
  or public.has_permission(institution_id, 'admissions.manage')
);

drop policy if exists "Admissions managers can manage admission cycles"
on public.admission_cycles;

create policy "Admissions managers can manage admission cycles"
on public.admission_cycles
for all
to authenticated
using (
  public.has_permission(institution_id, 'admissions.manage')
)
with check (
  public.has_permission(institution_id, 'admissions.manage')
);


drop policy if exists "Admissions viewers can view applicants"
on public.applicants;

create policy "Admissions viewers can view applicants"
on public.applicants
for select
to authenticated
using (
  public.has_permission(institution_id, 'admissions.view')
  or public.has_permission(institution_id, 'admissions.manage')
);

drop policy if exists "Admissions managers can manage applicants"
on public.applicants;

create policy "Admissions managers can manage applicants"
on public.applicants
for all
to authenticated
using (
  public.has_permission(institution_id, 'admissions.manage')
)
with check (
  public.has_permission(institution_id, 'admissions.manage')
);


drop policy if exists "Admissions viewers can view applications"
on public.applications;

create policy "Admissions viewers can view applications"
on public.applications
for select
to authenticated
using (
  public.has_permission(institution_id, 'admissions.view')
  or public.has_permission(institution_id, 'admissions.manage')
);

drop policy if exists "Admissions managers can manage applications"
on public.applications;

create policy "Admissions managers can manage applications"
on public.applications
for all
to authenticated
using (
  public.has_permission(institution_id, 'admissions.manage')
)
with check (
  public.has_permission(institution_id, 'admissions.manage')
);


drop policy if exists "Admissions viewers can view application choices"
on public.application_choices;

create policy "Admissions viewers can view application choices"
on public.application_choices
for select
to authenticated
using (
  public.has_permission(institution_id, 'admissions.view')
  or public.has_permission(institution_id, 'admissions.manage')
);

drop policy if exists "Admissions managers can manage application choices"
on public.application_choices;

create policy "Admissions managers can manage application choices"
on public.application_choices
for all
to authenticated
using (
  public.has_permission(institution_id, 'admissions.manage')
)
with check (
  public.has_permission(institution_id, 'admissions.manage')
);


-- ------------------------------------------------------------
-- Transactional internal application creator
-- ------------------------------------------------------------

create or replace function public.create_internal_admission_application(
  p_institution_id uuid,
  p_admission_cycle_id uuid,
  p_applicant_id uuid,
  p_entry_type text,
  p_first_programme_id uuid,
  p_second_programme_id uuid default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_prefix text;
  v_application_id uuid;
  v_application_number text;
begin
  if not public.has_permission(
    p_institution_id,
    'admissions.manage'
  ) then
    raise exception 'You do not have permission to manage admissions';
  end if;

  if not exists (
    select 1
    from public.admission_cycles ac
    where ac.id = p_admission_cycle_id
      and ac.institution_id = p_institution_id
  ) then
    raise exception 'Invalid admission cycle';
  end if;

  if not exists (
    select 1
    from public.applicants a
    where a.id = p_applicant_id
      and a.institution_id = p_institution_id
  ) then
    raise exception 'Invalid applicant';
  end if;

  if not exists (
    select 1
    from public.programmes p
    where p.id = p_first_programme_id
      and p.institution_id = p_institution_id
      and p.status = 'active'
  ) then
    raise exception 'Invalid first programme choice';
  end if;

  if p_second_programme_id is not null then
    if p_second_programme_id = p_first_programme_id then
      raise exception 'First and second programme choices must be different';
    end if;

    if not exists (
      select 1
      from public.programmes p
      where p.id = p_second_programme_id
        and p.institution_id = p_institution_id
        and p.status = 'active'
    ) then
      raise exception 'Invalid second programme choice';
    end if;
  end if;

  select coalesce(nullif(trim(ac.application_prefix), ''), 'APP')
  into v_prefix
  from public.admission_cycles ac
  where ac.id = p_admission_cycle_id;

  v_application_number :=
    upper(v_prefix)
    || '-'
    || to_char(current_date, 'YYYY')
    || '-'
    || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));

  insert into public.applications (
    institution_id,
    admission_cycle_id,
    applicant_id,
    application_number,
    entry_type,
    status,
    notes
  )
  values (
    p_institution_id,
    p_admission_cycle_id,
    p_applicant_id,
    v_application_number,
    coalesce(nullif(trim(p_entry_type), ''), 'regular'),
    'draft',
    p_notes
  )
  returning id into v_application_id;

  insert into public.application_choices (
    institution_id,
    application_id,
    programme_id,
    choice_order,
    status
  )
  values (
    p_institution_id,
    v_application_id,
    p_first_programme_id,
    1,
    'pending'
  );

  if p_second_programme_id is not null then
    insert into public.application_choices (
      institution_id,
      application_id,
      programme_id,
      choice_order,
      status
    )
    values (
      p_institution_id,
      v_application_id,
      p_second_programme_id,
      2,
      'pending'
    );
  end if;

  return jsonb_build_object(
    'id', v_application_id,
    'application_number', v_application_number
  );
end;
$$;

revoke all
on function public.create_internal_admission_application(
  uuid, uuid, uuid, text, uuid, uuid, text
)
from public;

grant execute
on function public.create_internal_admission_application(
  uuid, uuid, uuid, text, uuid, uuid, text
)
to authenticated;

notify pgrst, 'reload schema';
