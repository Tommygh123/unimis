-- ============================================================================
-- UniMIS Admissions Phase 2 - Compatibility + RLS
-- Local Docker development migration
--
-- Purpose:
--   1. Keep the EXISTING React admissions service/RPC names working.
--   2. Make existing application creation populate Phase 2 classification.
--   3. Route the old submit_admission_application RPC to Phase 2 validation.
--   4. Add RLS to the five Phase 2 support tables.
--   5. Preserve existing Paystack/offline-payment architecture.
--
-- This migration is intentionally conservative:
--   * no table drops
--   * no replacement of Paystack Edge Functions
--   * no replacement of existing payment RPCs
--   * no student-auth creation yet
-- ============================================================================

begin;

-- --------------------------------------------------------------------------
-- 1. Ensure RLS is enabled on Phase 2 support tables.
-- --------------------------------------------------------------------------
alter table public.admission_fee_rules enable row level security;
alter table public.admission_document_requirements enable row level security;
alter table public.application_reviews enable row level security;
alter table public.admission_cycle_counters enable row level security;
alter table public.student_number_counters enable row level security;

-- --------------------------------------------------------------------------
-- 2. Generic helper for institution membership.
--
-- We first try the existing UniMIS helper is_tenant_member(uuid), because the
-- earlier UniMIS foundation used institution/tenant membership helpers.
-- If unavailable, fall back to institution_users.
-- --------------------------------------------------------------------------
create or replace function public.unimis_is_institution_member(
    p_institution_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    v_ok boolean := false;
begin
    if auth.uid() is null or p_institution_id is null then
        return false;
    end if;

    -- Prefer the existing helper if present.
    if to_regprocedure('public.is_tenant_member(uuid)') is not null then
        begin
            execute 'select public.is_tenant_member($1)'
            into v_ok
            using p_institution_id;

            if coalesce(v_ok, false) then
                return true;
            end if;
        exception
            when others then
                v_ok := false;
        end;
    end if;

    -- Fallback to common UniMIS institution_users shape.
    if to_regclass('public.institution_users') is not null then
        begin
            execute $q$
                select exists (
                    select 1
                    from public.institution_users iu
                    where iu.institution_id = $1
                      and iu.user_id = auth.uid()
                      and coalesce(iu.status, 'active') = 'active'
                )
            $q$
            into v_ok
            using p_institution_id;
        exception
            when undefined_column then
                -- Some earlier schemas use profile_id rather than user_id.
                begin
                    execute $q$
                        select exists (
                            select 1
                            from public.institution_users iu
                            join public.profiles p on p.id = iu.profile_id
                            where iu.institution_id = $1
                              and p.id = auth.uid()
                              and coalesce(iu.status, 'active') = 'active'
                        )
                    $q$
                    into v_ok
                    using p_institution_id;
                exception
                    when others then
                        v_ok := false;
                end;
            when others then
                v_ok := false;
        end;
    end if;

    return coalesce(v_ok, false);
end;
$$;

revoke all on function public.unimis_is_institution_member(uuid) from public;
grant execute on function public.unimis_is_institution_member(uuid)
to authenticated, service_role;

-- --------------------------------------------------------------------------
-- 3. RLS policies for fee rules.
-- Staff/member access is deliberately aligned with the current internal
-- AdmissionsManagement screen. Applicant self-service policies will be added
-- when the public Applicant Portal is implemented.
-- --------------------------------------------------------------------------
drop policy if exists "Institution members can view admission fee rules"
on public.admission_fee_rules;
drop policy if exists "Institution members can manage admission fee rules"
on public.admission_fee_rules;

create policy "Institution members can view admission fee rules"
on public.admission_fee_rules
for select
to authenticated
using (public.unimis_is_institution_member(institution_id));

create policy "Institution members can manage admission fee rules"
on public.admission_fee_rules
for all
to authenticated
using (public.unimis_is_institution_member(institution_id))
with check (public.unimis_is_institution_member(institution_id));

-- --------------------------------------------------------------------------
-- 4. RLS policies for document requirements.
-- --------------------------------------------------------------------------
drop policy if exists "Institution members can view admission document requirements"
on public.admission_document_requirements;
drop policy if exists "Institution members can manage admission document requirements"
on public.admission_document_requirements;

create policy "Institution members can view admission document requirements"
on public.admission_document_requirements
for select
to authenticated
using (public.unimis_is_institution_member(institution_id));

create policy "Institution members can manage admission document requirements"
on public.admission_document_requirements
for all
to authenticated
using (public.unimis_is_institution_member(institution_id))
with check (public.unimis_is_institution_member(institution_id));

-- --------------------------------------------------------------------------
-- 5. RLS policies for application review history.
-- --------------------------------------------------------------------------
drop policy if exists "Institution members can view application reviews"
on public.application_reviews;
drop policy if exists "Institution members can create application reviews"
on public.application_reviews;

create policy "Institution members can view application reviews"
on public.application_reviews
for select
to authenticated
using (public.unimis_is_institution_member(institution_id));

create policy "Institution members can create application reviews"
on public.application_reviews
for insert
to authenticated
with check (public.unimis_is_institution_member(institution_id));

-- No ordinary UPDATE/DELETE policy: review history should remain historical.

-- --------------------------------------------------------------------------
-- 6. Counter tables are backend-only.
-- SECURITY DEFINER number functions write them; clients get no direct access.
-- --------------------------------------------------------------------------
revoke all on public.admission_cycle_counters from anon, authenticated;
revoke all on public.student_number_counters from anon, authenticated;

grant all on public.admission_cycle_counters to service_role;
grant all on public.student_number_counters to service_role;

-- --------------------------------------------------------------------------
-- 7. Grant access to the two configuration tables and review history.
-- RLS still decides which rows are accessible.
-- --------------------------------------------------------------------------
grant select, insert, update, delete
on public.admission_fee_rules
to authenticated;

grant select, insert, update, delete
on public.admission_document_requirements
to authenticated;

grant select, insert
on public.application_reviews
to authenticated;

-- --------------------------------------------------------------------------
-- 8. Existing submit_admission_application(uuid) compatibility
--
-- IMPORTANT:
-- The current UniMIS database already has submit_admission_application(uuid)
-- with an existing return type. PostgreSQL does not allow CREATE OR REPLACE
-- FUNCTION to change a function's return type.
--
-- We therefore PRESERVE the existing RPC in this migration.
-- After this migration succeeds, inspect its exact signature/return type using
-- the verification query at the bottom. We will then reconcile its body in a
-- separate safe migration without breaking the current React code.
-- --------------------------------------------------------------------------
do $$
begin
    if to_regprocedure('public.submit_admission_application(uuid)') is null then
        raise notice 'submit_admission_application(uuid) does not currently exist; frontend reconciliation will be handled separately.';
    else
        raise notice 'Preserving existing submit_admission_application(uuid) RPC and its current return type.';
    end if;
end $$;

-- --------------------------------------------------------------------------
-- 9. Compatibility trigger for applications created by the EXISTING
-- create_internal_admission_application RPC.
--
-- Phase 2 already has trg_unimis_prepare_application BEFORE INSERT.
-- This AFTER INSERT safeguard fills classification/payment values in case an
-- older RPC explicitly inserts null/default values in a way that needs syncing.
-- --------------------------------------------------------------------------
create or replace function public.unimis_sync_new_application_phase2()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_level text;
    v_scope text;
    v_category text;
    v_payment_required boolean;
begin
    select
        c.admission_level,
        c.applicant_scope,
        c.payment_required
    into
        v_level,
        v_scope,
        v_payment_required
    from public.admission_cycles c
    where c.id = new.admission_cycle_id;

    select a.applicant_category
    into v_category
    from public.applicants a
    where a.id = new.applicant_id;

    update public.applications
    set
        admission_level = coalesce(
            admission_level,
            case
                when v_level = 'both' then 'undergraduate'
                else v_level
            end
        ),
        applicant_category = coalesce(
            applicant_category,
            v_category,
            case
                when v_scope in ('local','international') then v_scope
                else 'local'
            end
        ),
        payment_status = coalesce(
            payment_status,
            case when coalesce(v_payment_required, true)
                 then 'pending'
                 else 'not_required'
            end
        ),
        decision_status = coalesce(decision_status, 'pending'),
        updated_at = now()
    where id = new.id
      and (
          admission_level is null
          or applicant_category is null
          or payment_status is null
          or decision_status is null
      );

    return new;
end;
$$;

drop trigger if exists trg_unimis_sync_new_application_phase2
on public.applications;

create trigger trg_unimis_sync_new_application_phase2
after insert on public.applications
for each row
execute function public.unimis_sync_new_application_phase2();

-- --------------------------------------------------------------------------
-- 10. Compatibility view for frontend configuration.
-- This gives React one clean read model for cycle + fee information without
-- removing the old settings.application_fee yet.
-- --------------------------------------------------------------------------
create or replace view public.admission_cycle_configuration
with (security_invoker = true)
as
select
    c.id,
    c.institution_id,
    c.academic_year_id,
    c.name,
    c.application_prefix,
    c.opens_at,
    c.closes_at,
    c.status,
    c.settings,
    c.admission_level,
    c.applicant_scope,
    c.max_programme_choices,
    c.payment_required,
    c.allow_draft_before_payment,
    c.application_instructions,
    fr.id as fee_rule_id,
    fr.programme_id as fee_programme_id,
    fr.applicant_category as fee_applicant_category,
    fr.admission_level as fee_admission_level,
    fr.amount as application_fee,
    fr.currency_code as fee_currency,
    fr.is_active as fee_is_active
from public.admission_cycles c
left join public.admission_fee_rules fr
  on fr.admission_cycle_id = c.id;

grant select on public.admission_cycle_configuration to authenticated;

-- --------------------------------------------------------------------------
-- 11. Backfill a general LOCAL UNDERGRADUATE fee rule from the OLD
-- admission_cycles.settings only when a positive legacy fee exists and no
-- equivalent Phase 2 rule exists.
--
-- This preserves previous cycle configuration without making JSON the new
-- source of truth.
-- --------------------------------------------------------------------------
insert into public.admission_fee_rules (
    institution_id,
    admission_cycle_id,
    programme_id,
    applicant_category,
    admission_level,
    amount,
    currency_code,
    is_active
)
select
    c.institution_id,
    c.id,
    null,
    'local',
    case
        when c.admission_level in ('undergraduate','postgraduate')
            then c.admission_level
        else 'undergraduate'
    end,
    case
        when (c.settings ->> 'application_fee') ~ '^[0-9]+([.][0-9]+)?$'
            then (c.settings ->> 'application_fee')::numeric
        else 0
    end,
    upper(coalesce(nullif(c.settings ->> 'currency',''), 'GHS')),
    true
from public.admission_cycles c
where coalesce(c.settings ->> 'application_fee','') ~ '^[0-9]+([.][0-9]+)?$'
  and (c.settings ->> 'application_fee')::numeric > 0
  and not exists (
      select 1
      from public.admission_fee_rules fr
      where fr.admission_cycle_id = c.id
        and fr.programme_id is null
        and fr.applicant_category = 'local'
        and fr.admission_level =
            case
                when c.admission_level in ('undergraduate','postgraduate')
                    then c.admission_level
                else 'undergraduate'
            end
  );

commit;

-- ============================================================================
-- VERIFICATION
-- ============================================================================

-- A. New Phase 2 policies
-- select tablename, policyname, cmd
-- from pg_policies
-- where schemaname='public'
--   and tablename in (
--     'admission_fee_rules',
--     'admission_document_requirements',
--     'application_reviews'
--   )
-- order by tablename, policyname;

-- B. Inspect the EXISTING submit RPC exactly
-- select
--   p.proname,
--   pg_get_function_identity_arguments(p.oid) as arguments,
--   pg_get_function_result(p.oid) as return_type,
--   l.lanname as language,
--   p.prosecdef as security_definer
-- from pg_proc p
-- join pg_namespace n on n.oid=p.pronamespace
-- join pg_language l on l.oid=p.prolang
-- where n.nspname='public'
--   and p.proname='submit_admission_application';

-- C. Confirm cycle configuration view
-- select
--   name,
--   admission_level,
--   applicant_scope,
--   max_programme_choices,
--   payment_required,
--   fee_applicant_category,
--   fee_admission_level,
--   application_fee,
--   fee_currency
-- from public.admission_cycle_configuration
-- order by name;

-- D. Confirm old payment RPCs still exist
-- select p.proname, pg_get_function_identity_arguments(p.oid)
-- from pg_proc p
-- join pg_namespace n on n.oid=p.pronamespace
-- where n.nspname='public'
--   and p.proname in (
--     'record_offline_admission_payment',
--     'verify_offline_admission_payment',
--     'create_internal_admission_application'
--   )
-- order by p.proname;
