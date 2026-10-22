-- UniMIS official student numbering
-- Uses the EXISTING trg_generate_student_number -> generate_student_number() architecture.
-- Format: FACULTY/DEPARTMENT/YY/NNN, e.g. FET/ECE/26/001
--
-- Existing student_number_counters remains:
--   institution_id, academic_year_id, last_number, updated_at
-- It is NOT repurposed because its current key cannot support independent department counters.

begin;

-- Dedicated counters for the new official numbering dimensions.
create table if not exists public.student_department_number_counters (
  institution_id uuid not null references public.institutions(id) on delete cascade,
  department_id uuid not null references public.departments(id) on delete cascade,
  admission_year integer not null,
  last_number bigint not null default 0,
  updated_at timestamptz not null default now(),
  primary key (institution_id, department_id, admission_year)
);

alter table public.student_department_number_counters enable row level security;

-- Keep the existing trigger name. Only replace the function it already calls.
create or replace function public.generate_student_number()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_programme_id uuid;
  v_department_id uuid;
  v_department_code text;
  v_faculty_code text;
  v_year integer;
  v_next bigint;
begin
  if new.student_number is null or btrim(new.student_number) = '' then

    if new.institution_id is null then
      raise exception 'Cannot generate student number: institution is missing.';
    end if;

    if new.application_id is null then
      raise exception 'Cannot generate student number: admission application is missing.';
    end if;

    -- Programme is taken from the accepted offer that caused conversion.
    select ao.programme_id
      into v_programme_id
    from public.admission_offers ao
    where ao.application_id = new.application_id
      and ao.response_status = 'accepted'
    order by coalesce(ao.responded_at, ao.created_at) desc
    limit 1;

    if v_programme_id is null then
      raise exception 'Cannot generate student number: no accepted programme offer found for application %.',
        new.application_id;
    end if;

    select d.id,
           upper(regexp_replace(coalesce(d.code,''), '[^A-Za-z0-9]', '', 'g')),
           upper(regexp_replace(coalesce(f.code,''), '[^A-Za-z0-9]', '', 'g'))
      into v_department_id, v_department_code, v_faculty_code
    from public.programmes p
    join public.departments d on d.id = p.department_id
    join public.faculties f on f.id = d.faculty_id
    where p.id = v_programme_id;

    if v_department_id is null then
      raise exception 'Cannot generate student number: programme % has no valid department.', v_programme_id;
    end if;

    if coalesce(v_department_code,'') = '' then
      raise exception 'Cannot generate student number: department code is missing.';
    end if;

    if coalesce(v_faculty_code,'') = '' then
      raise exception 'Cannot generate student number: faculty code is missing.';
    end if;

    -- Use the student's actual admission date when conversion supplies it.
    v_year := coalesce(
      extract(year from new.admission_date)::integer,
      extract(year from current_date)::integer
    );

    -- Atomic independent counter for institution + department + admission year.
    insert into public.student_department_number_counters
      (institution_id, department_id, admission_year, last_number, updated_at)
    values
      (new.institution_id, v_department_id, v_year, 1, now())
    on conflict (institution_id, department_id, admission_year)
    do update
       set last_number = public.student_department_number_counters.last_number + 1,
           updated_at = now()
    returning last_number into v_next;

    new.student_number :=
      v_faculty_code || '/' ||
      v_department_code || '/' ||
      right(v_year::text, 2) || '/' ||
      lpad(v_next::text, 3, '0');
  end if;

  return new;
end
$function$;

-- Preserve trg_generate_student_number exactly as the existing entry point.
-- Recreate only if it is absent.
do $$
begin
  if not exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'students'
      and t.tgname = 'trg_generate_student_number'
      and not t.tgisinternal
  ) then
    create trigger trg_generate_student_number
    before insert on public.students
    for each row execute function public.generate_student_number();
  end if;
end $$;

commit;
