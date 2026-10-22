
-- UniMIS WAEC verification workflow.
-- Uses the existing applicant_qualifications verification fields as the source of truth
-- and adds an auditable institutional verification history.

create table if not exists public.waec_verification_events (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  application_id uuid,
  applicant_id uuid not null,
  qualification_id uuid not null references public.applicant_qualifications(id) on delete cascade,
  verification_method text not null default 'waec_portal'
    check (verification_method in ('waec_portal','waec_bulk','waec_api','manual_evidence')),
  status text not null
    check (status in ('pending','verified','mismatch','failed')),
  reference text,
  notes text,
  official_result jsonb,
  comparison_result jsonb,
  performed_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);

create index if not exists waec_verification_events_qualification_idx
  on public.waec_verification_events(qualification_id, created_at desc);

alter table public.waec_verification_events enable row level security;

drop policy if exists "Institution staff can view WAEC verification events" on public.waec_verification_events;
create policy "Institution staff can view WAEC verification events"
on public.waec_verification_events for select to authenticated
using (
  exists (
    select 1 from public.institution_users iu
    where iu.institution_id = waec_verification_events.institution_id
      and iu.user_id = auth.uid()
  )
);

grant select on public.waec_verification_events to authenticated;

create or replace function public.unimis_record_waec_verification(
  p_qualification_id uuid,
  p_status text,
  p_method text default 'waec_portal',
  p_reference text default null,
  p_notes text default null,
  p_official_result jsonb default null,
  p_comparison_result jsonb default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  q public.applicant_qualifications%rowtype;
  app_id uuid;
  mapped_status text;
begin
  if p_status not in ('pending','verified','mismatch','failed') then
    raise exception 'Unsupported WAEC verification status';
  end if;
  if p_method not in ('waec_portal','waec_bulk','waec_api','manual_evidence') then
    raise exception 'Unsupported WAEC verification method';
  end if;

  select * into q
  from public.applicant_qualifications
  where id = p_qualification_id;

  if q.id is null then raise exception 'Qualification not found'; end if;

  if not exists (
    select 1 from public.institution_users iu
    where iu.institution_id = q.institution_id and iu.user_id = auth.uid()
  ) then
    raise exception 'Not authorized for this institution';
  end if;

  select a.id into app_id
  from public.applications a
  where a.applicant_id = q.applicant_id
    and a.institution_id = q.institution_id
  order by a.created_at desc
  limit 1;

  mapped_status := case
    when p_status = 'verified' then 'verified'
    when p_status = 'mismatch' then 'mismatch'
    else 'unverified'
  end;

  update public.applicant_qualifications
  set verification_status = mapped_status,
      verification_source = case
        when p_method = 'waec_api' then 'waec_api'
        when p_method = 'waec_bulk' then 'waec_bulk'
        when p_method = 'waec_portal' then 'waec_portal'
        else 'manual'
      end,
      verification_reference = nullif(trim(coalesce(p_reference,'')),''),
      verification_notes = nullif(trim(coalesce(p_notes,'')),''),
      verified_at = case when p_status = 'verified' then now() else null end,
      verified_by = case when p_status = 'verified' then auth.uid() else null end,
      updated_at = now()
  where id = q.id;

  insert into public.waec_verification_events(
    institution_id, application_id, applicant_id, qualification_id,
    verification_method, status, reference, notes, official_result, comparison_result
  ) values (
    q.institution_id, app_id, q.applicant_id, q.id,
    p_method, p_status, nullif(trim(coalesce(p_reference,'')),''),
    nullif(trim(coalesce(p_notes,'')),''), p_official_result, p_comparison_result
  );

  return true;
end;
$$;

grant execute on function public.unimis_record_waec_verification(uuid,text,text,text,text,jsonb,jsonb) to authenticated;
