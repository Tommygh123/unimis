-- ============================================================================
-- UniMIS Admissions Phase 2 - Migration 004
-- Reconcile existing submit_admission_application(uuid) RPC
--
-- Existing contract confirmed from database:
--   submit_admission_application(p_application_id uuid)
--   RETURNS boolean
--   LANGUAGE plpgsql
--   SECURITY DEFINER
--
-- This migration PRESERVES that exact public contract so the current React
-- Admissions code continues to work, while adding Phase 2 validation.
-- ============================================================================

begin;

create or replace function public.submit_admission_application(
    p_application_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
    v_app public.applications%rowtype;
    v_cycle public.admission_cycles%rowtype;
    v_applicant_user_id uuid;
    v_choice_count integer := 0;
    v_missing_count integer := 0;
    v_payment_ok boolean := false;
begin
    if p_application_id is null then
        raise exception 'Application ID is required.';
    end if;

    -- Lock application for safe one-time submission.
    select *
    into v_app
    from public.applications
    where id = p_application_id
    for update;

    if not found then
        raise exception 'Application not found.';
    end if;

    -- SECURITY DEFINER requires an explicit ownership/staff check.
    -- Applicant owner is accepted when applicants.user_id = auth.uid().
    select a.user_id
    into v_applicant_user_id
    from public.applicants a
    where a.id = v_app.applicant_id;

    if auth.role() <> 'service_role'
       and not public.unimis_is_institution_member(v_app.institution_id)
       and v_applicant_user_id is distinct from auth.uid() then
        raise exception 'You are not authorized to submit this application.'
            using errcode = '42501';
    end if;

    -- Idempotent behavior: if already submitted or beyond, report success.
    if lower(coalesce(v_app.status, '')) in (
        'submitted',
        'under_review',
        'reviewed',
        'qualified',
        'offered',
        'admitted',
        'accepted'
    ) then
        return true;
    end if;

    if lower(coalesce(v_app.status, 'draft')) not in (
        'draft',
        'incomplete',
        'returned'
    ) then
        raise exception
            'Application cannot be submitted from status "%".',
            v_app.status;
    end if;

    select *
    into v_cycle
    from public.admission_cycles
    where id = v_app.admission_cycle_id;

    if not found then
        raise exception 'Admission cycle not found.';
    end if;

    if lower(coalesce(v_cycle.status, '')) not in ('open', 'active') then
        raise exception 'Admission cycle is not open.';
    end if;

    if v_cycle.opens_at is not null and now() < v_cycle.opens_at then
        raise exception 'Admission cycle has not opened.';
    end if;

    if v_cycle.closes_at is not null and now() > v_cycle.closes_at then
        raise exception 'Admission cycle has closed.';
    end if;

    -- Ensure application classification agrees with cycle rules.
    if v_app.admission_level is null then
        raise exception 'Application admission level has not been selected.';
    end if;

    if v_app.applicant_category is null then
        raise exception 'Applicant category has not been selected.';
    end if;

    if v_cycle.admission_level <> 'both'
       and v_app.admission_level <> v_cycle.admission_level then
        raise exception
            'The selected admission level is not allowed for this cycle.';
    end if;

    if v_cycle.applicant_scope <> 'both'
       and v_app.applicant_category <> v_cycle.applicant_scope then
        raise exception
            'The applicant category is not allowed for this cycle.';
    end if;

    -- Programme choices.
    select count(*)
    into v_choice_count
    from public.application_choices ac
    where ac.application_id = p_application_id;

    if v_choice_count < 1 then
        raise exception 'At least one programme choice is required.';
    end if;

    if v_choice_count > coalesce(v_cycle.max_programme_choices, 3) then
        raise exception
            'Maximum programme choices allowed for this cycle: %.',
            v_cycle.max_programme_choices;
    end if;

    -- Required documents from the new Phase 2 rules.
    select count(*)
    into v_missing_count
    from public.unimis_missing_application_documents(p_application_id);

    if v_missing_count > 0 then
        raise exception
            '% required application document(s) are missing.',
            v_missing_count;
    end if;

    -- Application fee.
    if coalesce(v_cycle.payment_required, true) then
        v_payment_ok :=
            public.unimis_application_payment_confirmed(p_application_id);

        if not coalesce(v_payment_ok, false) then
            raise exception
                'Application fee has not been fully verified.';
        end if;
    else
        v_payment_ok := true;
    end if;

    -- Submit and lock.
    update public.applications
    set
        status = 'submitted',
        payment_status =
            case
                when coalesce(v_cycle.payment_required, true)
                    then 'paid'
                else 'not_required'
            end,
        submitted_at = coalesce(submitted_at, now()),
        submitted_locked_at = coalesce(submitted_locked_at, now()),
        decision_status = coalesce(decision_status, 'pending'),
        updated_at = now()
    where id = p_application_id;

    return true;
end;
$$;

-- Preserve the existing RPC exposure.
revoke all on function public.submit_admission_application(uuid) from public;
grant execute on function public.submit_admission_application(uuid)
to authenticated, service_role;

comment on function public.submit_admission_application(uuid) is
'UniMIS Phase 2 application submission RPC. Preserves legacy boolean return contract while validating cycle, applicant category, admission level, programme choices, required documents and verified application fee.';

commit;

-- ============================================================================
-- VERIFICATION
-- ============================================================================

-- 1. Confirm the public contract is still exactly boolean:
-- select
--   p.proname,
--   pg_get_function_identity_arguments(p.oid) as arguments,
--   pg_get_function_result(p.oid) as return_type,
--   l.lanname as language,
--   p.prosecdef as security_definer
-- from pg_proc p
-- join pg_namespace n on n.oid = p.pronamespace
-- join pg_language l on l.oid = p.prolang
-- where n.nspname = 'public'
--   and p.proname = 'submit_admission_application';

-- Expected:
-- submit_admission_application | p_application_id uuid | boolean | plpgsql | true

-- 2. Confirm Phase 2 support functions exist:
-- select
--   p.proname,
--   pg_get_function_identity_arguments(p.oid) as arguments,
--   pg_get_function_result(p.oid) as return_type
-- from pg_proc p
-- join pg_namespace n on n.oid=p.pronamespace
-- where n.nspname='public'
--   and p.proname in (
--      'unimis_application_payment_confirmed',
--      'unimis_missing_application_documents',
--      'unimis_is_institution_member'
--   )
-- order by p.proname;
