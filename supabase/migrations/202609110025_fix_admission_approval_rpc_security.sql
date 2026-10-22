-- UniMIS: secure and fix approval/offer RPC
-- Root cause: unimis_approve_admission_recommendation was SECURITY INVOKER.
-- The authenticated browser role therefore needed direct table privileges on
-- admission_offers, causing "permission denied for table admission_offers".
--
-- Fix:
--   * make the workflow RPC SECURITY DEFINER
--   * add explicit admissions.manage permission check
--   * preserve controlled RPC-only offer creation
--   * do NOT grant direct INSERT/UPDATE/DELETE on admission_offers to browser users

create or replace function public.unimis_approve_admission_recommendation(
    p_application_id uuid,
    p_action text,
    p_programme_id uuid default null,
    p_comments text default null,
    p_conditions text default null,
    p_expires_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
    v_app public.applications%rowtype;
    v_rec public.application_reviews%rowtype;
    v_offer public.admission_offers%rowtype;
begin
    if p_action not in ('approve_offer','reject','waitlist','return_for_review') then
        raise exception 'Unsupported approval action.';
    end if;

    select *
    into v_app
    from public.applications
    where id = p_application_id
    for update;

    if not found then
        raise exception 'Application not found.';
    end if;

    if not public.has_permission(v_app.institution_id,'admissions.manage') then
        raise exception 'You do not have permission to approve admissions decisions.';
    end if;

    select *
    into v_rec
    from public.application_reviews
    where application_id = p_application_id
      and review_stage = 'recommendation'
      and action = 'submitted'
    order by created_at desc
    limit 1;

    if not found then
        raise exception 'No admissions recommendation has been submitted.';
    end if;

    if p_action = 'approve_offer' then
        if p_programme_id is null then
            p_programme_id := nullif(v_rec.metadata->>'programme_id','')::uuid;
        end if;

        if p_programme_id is null then
            raise exception 'Select the programme to offer.';
        end if;

        if exists (
            select 1
            from public.admission_offers ao
            where ao.application_id = p_application_id
              and ao.response_status in ('pending','accepted')
        ) then
            raise exception 'This application already has an active admission offer.';
        end if;

        select *
        into v_offer
        from public.unimis_create_admission_offer(
            p_application_id,
            p_programme_id,
            'regular',
            p_conditions,
            p_expires_at
        );

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
        ) values (
            v_app.institution_id,
            v_app.id,
            'approval',
            'approved_offer',
            v_app.decision_status,
            'offered',
            v_rec.recommendation,
            p_comments,
            auth.uid(),
            jsonb_build_object(
                'offer_id', v_offer.id,
                'offer_number', v_offer.offer_number,
                'programme_id', p_programme_id
            )
        );

        return jsonb_build_object(
            'action','approved_offer',
            'offer_id',v_offer.id,
            'offer_number',v_offer.offer_number
        );

    elsif p_action = 'reject' then
        perform public.unimis_record_application_decision(
            p_application_id,'rejected',p_comments
        );

    elsif p_action = 'waitlist' then
        perform public.unimis_record_application_decision(
            p_application_id,'waitlisted',p_comments
        );

    else
        update public.applications
        set decision_status='under_review',
            updated_at=now()
        where id=p_application_id;
    end if;

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
        'approval',
        p_action,
        v_app.decision_status,
        case p_action
          when 'reject' then 'rejected'
          when 'waitlist' then 'waitlisted'
          else 'under_review'
        end,
        v_rec.recommendation,
        p_comments,
        auth.uid()
    );

    return jsonb_build_object(
        'action',p_action,
        'application_id',v_app.id
    );
end;
$function$;

revoke all on function public.unimis_approve_admission_recommendation(
    uuid,text,uuid,text,text,timestamptz
) from public;

grant execute on function public.unimis_approve_admission_recommendation(
    uuid,text,uuid,text,text,timestamptz
) to authenticated;
