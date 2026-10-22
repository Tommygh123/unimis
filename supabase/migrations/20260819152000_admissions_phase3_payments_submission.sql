-- ============================================================
-- UniMIS Admissions Phase 3
-- Application Fee Payment + Submission
-- ============================================================

create table if not exists public.admission_application_payments (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  application_id uuid not null references public.applications(id) on delete cascade,
  amount numeric(12,2) not null check (amount > 0),
  currency text not null default 'GHS',
  channel text not null check (channel in ('online','offline')),
  payment_method text not null,
  provider text,
  provider_reference text,
  status text not null default 'pending'
    check (status in ('pending','verified','failed','cancelled','refunded')),
  paid_at timestamptz,
  recorded_by uuid references auth.users(id),
  verified_by uuid references auth.users(id),
  verified_at timestamptz,
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_admission_application_payments_application
on public.admission_application_payments(application_id);

create index if not exists idx_admission_application_payments_institution
on public.admission_application_payments(institution_id);

create unique index if not exists uq_admission_payment_provider_reference
on public.admission_application_payments(provider, provider_reference)
where provider_reference is not null;


grant select, insert, update
on table public.admission_application_payments
to authenticated;

alter table public.admission_application_payments enable row level security;

drop policy if exists "Admissions viewers can view application payments"
on public.admission_application_payments;

create policy "Admissions viewers can view application payments"
on public.admission_application_payments
for select
to authenticated
using (
  public.has_permission(institution_id, 'admissions.view')
  or public.has_permission(institution_id, 'admissions.manage')
);

drop policy if exists "Admissions managers can manage application payments"
on public.admission_application_payments;

create policy "Admissions managers can manage application payments"
on public.admission_application_payments
for all
to authenticated
using (
  public.has_permission(institution_id, 'admissions.manage')
)
with check (
  public.has_permission(institution_id, 'admissions.manage')
);


-- ------------------------------------------------------------
-- Record offline/walk-in payment.
-- Payment remains pending until explicitly verified.
-- ------------------------------------------------------------

create or replace function public.record_offline_admission_payment(
  p_application_id uuid,
  p_amount numeric,
  p_currency text,
  p_payment_method text,
  p_provider text default null,
  p_provider_reference text default null,
  p_paid_at timestamptz default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_institution_id uuid;
  v_payment_id uuid;
begin
  select institution_id
  into v_institution_id
  from public.applications
  where id = p_application_id;

  if v_institution_id is null then
    raise exception 'Application not found';
  end if;

  if not public.has_permission(v_institution_id, 'admissions.manage') then
    raise exception 'You do not have permission to record admission payments';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Payment amount must be greater than zero';
  end if;

  insert into public.admission_application_payments (
    institution_id,
    application_id,
    amount,
    currency,
    channel,
    payment_method,
    provider,
    provider_reference,
    status,
    paid_at,
    recorded_by,
    notes
  )
  values (
    v_institution_id,
    p_application_id,
    p_amount,
    upper(coalesce(nullif(trim(p_currency), ''), 'GHS')),
    'offline',
    coalesce(nullif(trim(p_payment_method), ''), 'other'),
    nullif(trim(p_provider), ''),
    nullif(trim(p_provider_reference), ''),
    'pending',
    coalesce(p_paid_at, now()),
    auth.uid(),
    p_notes
  )
  returning id into v_payment_id;

  return v_payment_id;
end;
$$;

revoke all
on function public.record_offline_admission_payment(
  uuid, numeric, text, text, text, text, timestamptz, text
)
from public;

grant execute
on function public.record_offline_admission_payment(
  uuid, numeric, text, text, text, text, timestamptz, text
)
to authenticated;


-- ------------------------------------------------------------
-- Verify an offline payment.
-- ------------------------------------------------------------

create or replace function public.verify_offline_admission_payment(
  p_payment_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_institution_id uuid;
  v_channel text;
begin
  select institution_id, channel
  into v_institution_id, v_channel
  from public.admission_application_payments
  where id = p_payment_id;

  if v_institution_id is null then
    raise exception 'Payment not found';
  end if;

  if v_channel <> 'offline' then
    raise exception 'Only offline payments can be manually verified';
  end if;

  if not public.has_permission(v_institution_id, 'admissions.manage') then
    raise exception 'You do not have permission to verify admission payments';
  end if;

  update public.admission_application_payments
  set
    status = 'verified',
    verified_by = auth.uid(),
    verified_at = now(),
    updated_at = now()
  where id = p_payment_id;

  return true;
end;
$$;

revoke all
on function public.verify_offline_admission_payment(uuid)
from public;

grant execute
on function public.verify_offline_admission_payment(uuid)
to authenticated;


-- ------------------------------------------------------------
-- Submit application.
-- We intentionally use submitted_at as the reliable workflow marker
-- rather than assuming an existing applications.status constraint.
-- ------------------------------------------------------------

create or replace function public.submit_admission_application(
  p_application_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_institution_id uuid;
  v_cycle_id uuid;
  v_fee numeric;
  v_currency text;
begin
  select institution_id, admission_cycle_id
  into v_institution_id, v_cycle_id
  from public.applications
  where id = p_application_id;

  if v_institution_id is null then
    raise exception 'Application not found';
  end if;

  if not public.has_permission(v_institution_id, 'admissions.manage') then
    raise exception 'You do not have permission to submit this application';
  end if;

  select
    coalesce((settings ->> 'application_fee')::numeric, 0),
    coalesce(settings ->> 'currency', 'GHS')
  into v_fee, v_currency
  from public.admission_cycles
  where id = v_cycle_id;

  if v_fee > 0 and not exists (
    select 1
    from public.admission_application_payments p
    where p.application_id = p_application_id
      and p.status = 'verified'
      and upper(p.currency) = upper(v_currency)
      and p.amount >= v_fee
  ) then
    raise exception 'Verified application fee payment is required before submission';
  end if;

  if not exists (
    select 1
    from public.application_choices c
    where c.application_id = p_application_id
      and c.choice_order = 1
  ) then
    raise exception 'At least one programme choice is required';
  end if;

  update public.applications
  set
    submitted_at = coalesce(submitted_at, now()),
    updated_at = now()
  where id = p_application_id;

  return true;
end;
$$;

revoke all
on function public.submit_admission_application(uuid)
from public;

grant execute
on function public.submit_admission_application(uuid)
to authenticated;

notify pgrst, 'reload schema';
