
create or replace function public.unimis_submit_admission_recommendation(
    p_application_id uuid,
    p_programme_id uuid,
    p_recommendation text,
    p_comments text default null
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
    v_app public.applications%rowtype;
    v_has_wassce boolean := false;
    v_waec_ready boolean := true;
    v_review_id uuid;
begin
    if p_recommendation not in ('recommend_offer','recommend_reject','waitlist','hold') then
        raise exception 'Unsupported recommendation.';
    end if;

    select * into v_app
    from public.applications
    where id = p_application_id
    for update;

    if not found then raise exception 'Application not found.'; end if;
    if v_app.submitted_at is null then raise exception 'Application has not been submitted.'; end if;
    if v_app.reviewed_at is null then raise exception 'Complete the admissions review before recommendation.'; end if;

    if p_programme_id is not null and not exists (
        select 1 from public.application_choices ac
        where ac.application_id = p_application_id
          and ac.programme_id = p_programme_id
    ) then
        raise exception 'Recommended programme must be one of the applicant choices.';
    end if;

    select exists (
        select 1
        from public.applicant_qualifications q
        join public.applicant_subject_results sr on sr.qualification_id = q.id
        where q.applicant_id = v_app.applicant_id
          and upper(coalesce(q.qualification_type,'')) = 'WASSCE'
    ) into v_has_wassce;

    if v_has_wassce then
        select not exists (
            select 1
            from public.applicant_qualifications q
            where q.applicant_id = v_app.applicant_id
              and upper(coalesce(q.qualification_type,'')) = 'WASSCE'
              and exists (
                  select 1 from public.applicant_subject_results sr
                  where sr.qualification_id = q.id
              )
              and not (
                  q.verification_status = 'verified'
                  and lower(coalesce(q.verification_source,'')) in ('waec_portal','waec_bulk','waec_api')
              )
        ) into v_waec_ready;

        if not v_waec_ready then
            raise exception 'Official WAEC verification is required before recommendation.';
        end if;
    end if;

    insert into public.application_reviews (
        institution_id, application_id, review_stage, action,
        old_status, new_status, recommendation, comments, reviewed_by, metadata
    )
    values (
        v_app.institution_id, v_app.id, 'recommendation', 'submitted',
        v_app.decision_status, 'under_review', p_recommendation, p_comments, auth.uid(),
        jsonb_build_object('programme_id', p_programme_id)
    )
    returning id into v_review_id;

    update public.applications
    set decision_status = 'under_review',
        decision_at = now(),
        decision_by = auth.uid(),
        updated_at = now()
    where id = v_app.id;

    return jsonb_build_object(
        'review_id', v_review_id,
        'application_id', v_app.id,
        'recommendation', p_recommendation,
        'programme_id', p_programme_id,
        'waec_verified', v_waec_ready
    );
end;
$$;

grant execute on function public.unimis_submit_admission_recommendation(uuid,uuid,text,text) to authenticated;

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
security invoker
set search_path = public
as $$
declare
    v_app public.applications%rowtype;
    v_rec public.application_reviews%rowtype;
    v_offer public.admission_offers%rowtype;
begin
    if p_action not in ('approve_offer','reject','waitlist','return_for_review') then
        raise exception 'Unsupported approval action.';
    end if;

    select * into v_app
    from public.applications
    where id = p_application_id
    for update;

    if not found then raise exception 'Application not found.'; end if;

    select * into v_rec
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

        select * into v_offer
        from public.unimis_create_admission_offer(
            p_application_id,
            p_programme_id,
            'regular',
            p_conditions,
            p_expires_at
        );

        insert into public.application_reviews (
            institution_id, application_id, review_stage, action,
            old_status, new_status, recommendation, comments, reviewed_by, metadata
        ) values (
            v_app.institution_id, v_app.id, 'approval', 'approved_offer',
            v_app.decision_status, 'offered', v_rec.recommendation, p_comments, auth.uid(),
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
        institution_id, application_id, review_stage, action,
        old_status, new_status, recommendation, comments, reviewed_by
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
$$;

grant execute on function public.unimis_approve_admission_recommendation(uuid,text,uuid,text,text,timestamptz) to authenticated;
