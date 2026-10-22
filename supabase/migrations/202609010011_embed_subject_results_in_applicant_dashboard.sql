-- UniMIS: make qualification editing deterministic by embedding saved subject grades
-- directly in unimis_applicant_dashboard().
-- This removes the UI dependency on a second subject-results fetch.

create or replace function public.unimis_applicant_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_applicant public.applicants%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.' using errcode='42501';
  end if;

  select * into v_applicant
  from public.applicants
  where user_id=auth.uid()
  order by created_at
  limit 1;

  if not found then
    return jsonb_build_object(
      'applicant',null,'applications','[]'::jsonb,'qualifications','[]'::jsonb
    );
  end if;

  return jsonb_build_object(
    'applicant',to_jsonb(v_applicant),
    'qualifications',coalesce((
      select jsonb_agg(
        to_jsonb(q) || jsonb_build_object(
          'subject_results',coalesce((
            select jsonb_agg(to_jsonb(sr) order by sr.created_at, sr.subject_name)
            from public.applicant_subject_results sr
            where sr.qualification_id=q.id
          ),'[]'::jsonb)
        )
        order by q.created_at desc
      )
      from public.applicant_qualifications q
      where q.applicant_id=v_applicant.id
    ),'[]'::jsonb),
    'applications',coalesce((
      select jsonb_agg(
        to_jsonb(ap) || jsonb_build_object(
          'cycle',(select jsonb_build_object(
            'id',c.id,'name',c.name,'status',c.status,
            'admission_level',c.admission_level,'applicant_scope',c.applicant_scope,
            'max_programme_choices',c.max_programme_choices,
            'payment_required',c.payment_required,
            'application_instructions',c.application_instructions
          ) from public.admission_cycles c where c.id=ap.admission_cycle_id),
          'choices',coalesce((
            select jsonb_agg(jsonb_build_object(
              'id',ch.id,'choice_order',ch.choice_order,'status',ch.status,
              'programme',jsonb_build_object(
                'id',p.id,'name',p.name,'code',p.code,
                'award_type',p.award_type,'admission_level',p.admission_level
              )
            ) order by ch.choice_order)
            from public.application_choices ch
            join public.programmes p on p.id=ch.programme_id
            where ch.application_id=ap.id
          ),'[]'::jsonb),
          'documents',coalesce((
            select jsonb_agg(to_jsonb(d) order by d.created_at desc)
            from public.application_documents d where d.application_id=ap.id
          ),'[]'::jsonb),
          'payments',coalesce((
            select jsonb_agg(to_jsonb(py) order by py.created_at desc)
            from public.admission_application_payments py where py.application_id=ap.id
          ),'[]'::jsonb),
          'offers',coalesce((
            select jsonb_agg(
              to_jsonb(o) || jsonb_build_object(
                'programme',jsonb_build_object('id',p.id,'name',p.name,'code',p.code)
              )
              order by o.offered_at desc
            )
            from public.admission_offers o
            join public.programmes p on p.id=o.programme_id
            where o.application_id=ap.id
          ),'[]'::jsonb)
        )
        order by ap.created_at desc
      )
      from public.applications ap
      where ap.applicant_id=v_applicant.id
    ),'[]'::jsonb)
  );
end;
$$;


revoke all on function public.unimis_applicant_dashboard() from public;
grant execute on function public.unimis_applicant_dashboard() to authenticated,service_role;
