begin;

alter table public.programmes add column if not exists admission_level text;
alter table public.programmes add column if not exists accepts_local boolean;
alter table public.programmes add column if not exists accepts_international boolean;

update public.programmes
set admission_level = coalesce(
      admission_level,
      case when lower(coalesce(award_type,'')) ~ '(phd|doctor|master|msc|ma|mphil|mba|mtech|postgraduate|pgdip)'
           then 'postgraduate' else 'undergraduate' end),
    accepts_local = coalesce(accepts_local,true),
    accepts_international = coalesce(accepts_international,true)
where admission_level is null
   or accepts_local is null
   or accepts_international is null;

alter table public.programmes
  alter column admission_level set default 'undergraduate',
  alter column accepts_local set default true,
  alter column accepts_international set default true;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='programmes_admission_level_chk'
      and conrelid='public.programmes'::regclass
  ) then
    alter table public.programmes
    add constraint programmes_admission_level_chk
    check (admission_level in ('undergraduate','postgraduate'));
  end if;
end $$;

create or replace function public.unimis_my_applicant_id()
returns uuid
language sql
stable
security definer
set search_path=public
as $$
  select a.id
  from public.applicants a
  where a.user_id=auth.uid()
  order by a.created_at
  limit 1;
$$;

create or replace function public.unimis_applicant_owns_application(p_application_id uuid)
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select exists (
    select 1
    from public.applications ap
    join public.applicants a on a.id=ap.applicant_id
    where ap.id=p_application_id
      and a.user_id=auth.uid()
  );
$$;

revoke all on function public.unimis_my_applicant_id() from public;
revoke all on function public.unimis_applicant_owns_application(uuid) from public;
grant execute on function public.unimis_my_applicant_id() to authenticated, service_role;
grant execute on function public.unimis_applicant_owns_application(uuid) to authenticated, service_role;

create or replace function public.unimis_admissions_public_bootstrap()
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_inst public.institutions%rowtype;
begin
  select * into v_inst
  from public.institutions
  where status='active'
  order by created_at
  limit 1;

  if not found then
    return jsonb_build_object(
      'institution',null,
      'cycles','[]'::jsonb,
      'programmes','[]'::jsonb,
      'fee_rules','[]'::jsonb,
      'document_requirements','[]'::jsonb
    );
  end if;

  return jsonb_build_object(
    'institution',jsonb_build_object(
      'id',v_inst.id,'name',v_inst.name,'short_name',v_inst.short_name,
      'code',v_inst.code,'email',v_inst.email,'phone',v_inst.phone,
      'website',v_inst.website,'country',v_inst.country,
      'currency_code',v_inst.currency_code,'logo_url',v_inst.logo_url
    ),
    'cycles',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',c.id,'name',c.name,'academic_year_id',c.academic_year_id,
        'application_prefix',c.application_prefix,'opens_at',c.opens_at,
        'closes_at',c.closes_at,'status',c.status,
        'admission_level',c.admission_level,'applicant_scope',c.applicant_scope,
        'max_programme_choices',c.max_programme_choices,
        'payment_required',c.payment_required,
        'allow_draft_before_payment',c.allow_draft_before_payment,
        'application_instructions',c.application_instructions
      ) order by c.opens_at nulls first,c.name)
      from public.admission_cycles c
      where c.institution_id=v_inst.id
        and c.status in ('open','active')
        and (c.opens_at is null or c.opens_at<=now())
        and (c.closes_at is null or c.closes_at>=now())
    ),'[]'::jsonb),
    'programmes',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',p.id,'name',p.name,'code',p.code,'award_type',p.award_type,
        'department_id',p.department_id,'admission_level',p.admission_level,
        'accepts_local',p.accepts_local,
        'accepts_international',p.accepts_international
      ) order by p.name)
      from public.programmes p
      where p.institution_id=v_inst.id and p.status='active'
    ),'[]'::jsonb),
    'fee_rules',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',f.id,'admission_cycle_id',f.admission_cycle_id,
        'programme_id',f.programme_id,'applicant_category',f.applicant_category,
        'admission_level',f.admission_level,'amount',f.amount,
        'currency_code',f.currency_code
      ))
      from public.admission_fee_rules f
      where f.institution_id=v_inst.id and f.is_active=true
        and (f.effective_from is null or f.effective_from<=now())
        and (f.effective_to is null or f.effective_to>=now())
    ),'[]'::jsonb),
    'document_requirements',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',r.id,'admission_cycle_id',r.admission_cycle_id,
        'programme_id',r.programme_id,'applicant_category',r.applicant_category,
        'admission_level',r.admission_level,'document_type',r.document_type,
        'display_name',r.display_name,'description',r.description,
        'is_required',r.is_required,'requires_verification',r.requires_verification,
        'accepted_mime_types',r.accepted_mime_types,
        'max_file_size_bytes',r.max_file_size_bytes,'sequence_no',r.sequence_no
      ) order by r.sequence_no,r.display_name)
      from public.admission_document_requirements r
      where r.institution_id=v_inst.id and r.is_active=true
    ),'[]'::jsonb)
  );
end;
$$;

revoke all on function public.unimis_admissions_public_bootstrap() from public;
grant execute on function public.unimis_admissions_public_bootstrap() to anon,authenticated,service_role;

create or replace function public.unimis_applicant_save_profile(
  p_institution_id uuid,
  p_first_name text,
  p_middle_name text,
  p_last_name text,
  p_date_of_birth date,
  p_gender text,
  p_phone text,
  p_nationality text,
  p_country_of_residence text,
  p_address text,
  p_city text,
  p_region text,
  p_applicant_category text,
  p_national_id_type text default null,
  p_national_id_number text default null,
  p_passport_number text default null,
  p_passport_expiry_date date default null,
  p_country_of_birth text default null,
  p_residency_status text default null
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_id uuid;
  v_email text;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.' using errcode='42501';
  end if;

  if p_applicant_category not in ('local','international') then
    raise exception 'Applicant category must be local or international.';
  end if;

  if not exists(select 1 from public.institutions where id=p_institution_id and status='active') then
    raise exception 'Institution is not available.';
  end if;

  v_email:=lower(coalesce(auth.jwt()->>'email',''));

  select id into v_id
  from public.applicants
  where user_id=auth.uid()
  order by created_at
  limit 1;

  if v_id is null then
    insert into public.applicants(
      institution_id,user_id,first_name,middle_name,last_name,date_of_birth,
      gender,email,phone,nationality,country_of_residence,address,city,region,
      applicant_category,national_id_type,national_id_number,passport_number,
      passport_expiry_date,country_of_birth,residency_status
    )
    values(
      p_institution_id,auth.uid(),trim(p_first_name),nullif(trim(p_middle_name),''),
      trim(p_last_name),p_date_of_birth,nullif(trim(p_gender),''),
      nullif(v_email,''),nullif(trim(p_phone),''),
      coalesce(nullif(trim(p_nationality),''),'Ghanaian'),
      coalesce(nullif(trim(p_country_of_residence),''),'Ghana'),
      nullif(trim(p_address),''),nullif(trim(p_city),''),
      nullif(trim(p_region),''),p_applicant_category,
      nullif(trim(p_national_id_type),''),nullif(trim(p_national_id_number),''),
      nullif(trim(p_passport_number),''),p_passport_expiry_date,
      nullif(trim(p_country_of_birth),''),nullif(trim(p_residency_status),'')
    )
    returning id into v_id;
  else
    update public.applicants set
      institution_id=p_institution_id,
      first_name=trim(p_first_name),
      middle_name=nullif(trim(p_middle_name),''),
      last_name=trim(p_last_name),
      date_of_birth=p_date_of_birth,
      gender=nullif(trim(p_gender),''),
      email=coalesce(nullif(v_email,''),email),
      phone=nullif(trim(p_phone),''),
      nationality=coalesce(nullif(trim(p_nationality),''),nationality),
      country_of_residence=coalesce(nullif(trim(p_country_of_residence),''),country_of_residence),
      address=nullif(trim(p_address),''),
      city=nullif(trim(p_city),''),
      region=nullif(trim(p_region),''),
      applicant_category=p_applicant_category,
      national_id_type=nullif(trim(p_national_id_type),''),
      national_id_number=nullif(trim(p_national_id_number),''),
      passport_number=nullif(trim(p_passport_number),''),
      passport_expiry_date=p_passport_expiry_date,
      country_of_birth=nullif(trim(p_country_of_birth),''),
      residency_status=nullif(trim(p_residency_status),''),
      updated_at=now()
    where id=v_id;
  end if;

  return v_id;
end;
$$;

grant execute on function public.unimis_applicant_save_profile(
  uuid,text,text,text,date,text,text,text,text,text,text,text,text,text,text,text,date,text,text
) to authenticated,service_role;

create or replace function public.unimis_applicant_create_application(
  p_admission_cycle_id uuid,
  p_programme_ids uuid[],
  p_entry_type text default 'regular',
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_applicant public.applicants%rowtype;
  v_cycle public.admission_cycles%rowtype;
  v_app_id uuid;
  v_programme_id uuid;
  v_pos bigint;
  v_count integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.' using errcode='42501';
  end if;

  select * into v_applicant
  from public.applicants
  where user_id=auth.uid()
  order by created_at
  limit 1;

  if not found then raise exception 'Complete your applicant profile first.'; end if;

  select * into v_cycle
  from public.admission_cycles
  where id=p_admission_cycle_id
    and institution_id=v_applicant.institution_id;

  if not found then raise exception 'Admission cycle is not available.'; end if;

  if v_cycle.status not in ('open','active')
     or (v_cycle.opens_at is not null and now()<v_cycle.opens_at)
     or (v_cycle.closes_at is not null and now()>v_cycle.closes_at) then
    raise exception 'Admission cycle is not currently open.';
  end if;

  if v_cycle.applicant_scope<>'both'
     and v_cycle.applicant_scope<>v_applicant.applicant_category then
    raise exception 'This admission cycle does not accept your applicant category.';
  end if;

  v_count:=coalesce(array_length(p_programme_ids,1),0);
  if v_count<1 then raise exception 'Select at least one programme.'; end if;
  if v_count>coalesce(v_cycle.max_programme_choices,3) then
    raise exception 'Maximum programme choices allowed: %.',v_cycle.max_programme_choices;
  end if;

  if exists(
    select 1
    from unnest(p_programme_ids) x(id)
    left join public.programmes p on p.id=x.id
    where p.id is null
       or p.institution_id<>v_applicant.institution_id
       or p.status<>'active'
       or (v_cycle.admission_level<>'both' and p.admission_level<>v_cycle.admission_level)
       or (v_applicant.applicant_category='local' and p.accepts_local=false)
       or (v_applicant.applicant_category='international' and p.accepts_international=false)
  ) then
    raise exception 'One or more selected programmes are not eligible for this application.';
  end if;

  if exists(
    select 1 from public.applications ap
    where ap.applicant_id=v_applicant.id
      and ap.admission_cycle_id=v_cycle.id
      and lower(ap.status) not in ('withdrawn','cancelled')
  ) then
    raise exception 'You already have an application for this admission cycle.';
  end if;

  insert into public.applications(
    institution_id,admission_cycle_id,applicant_id,entry_type,status,notes,
    admission_level,applicant_category,payment_status,decision_status
  )
  values(
    v_applicant.institution_id,v_cycle.id,v_applicant.id,
    coalesce(nullif(trim(p_entry_type),''),'regular'),'draft',nullif(trim(p_notes),''),
    case when v_cycle.admission_level='both'
         then (select admission_level from public.programmes where id=p_programme_ids[1])
         else v_cycle.admission_level end,
    v_applicant.applicant_category,
    case when v_cycle.payment_required then 'pending' else 'not_required' end,
    'pending'
  )
  returning id into v_app_id;

  for v_programme_id,v_pos in
    select id,ordinality
    from unnest(p_programme_ids) with ordinality as u(id,ordinality)
  loop
    insert into public.application_choices(
      institution_id,application_id,programme_id,choice_order,status
    )
    values(v_applicant.institution_id,v_app_id,v_programme_id,v_pos,'pending');
  end loop;

  return v_app_id;
end;
$$;

grant execute on function public.unimis_applicant_create_application(uuid,uuid[],text,text)
to authenticated,service_role;

create or replace function public.unimis_applicant_add_qualification(
  p_qualification_type text,
  p_institution_name text default null,
  p_examining_body text default null,
  p_index_number text default null,
  p_completion_year integer default null,
  p_overall_result text default null,
  p_details jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_applicant public.applicants%rowtype;
  v_id uuid;
begin
  select * into v_applicant
  from public.applicants
  where user_id=auth.uid()
  order by created_at
  limit 1;

  if not found then raise exception 'Applicant profile not found.'; end if;

  insert into public.applicant_qualifications(
    institution_id,applicant_id,qualification_type,institution_name,
    examining_body,index_number,completion_year,overall_result,details
  )
  values(
    v_applicant.institution_id,v_applicant.id,trim(p_qualification_type),
    nullif(trim(p_institution_name),''),nullif(trim(p_examining_body),''),
    nullif(trim(p_index_number),''),p_completion_year,
    nullif(trim(p_overall_result),''),coalesce(p_details,'{}'::jsonb)
  )
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function public.unimis_applicant_add_qualification(text,text,text,text,integer,text,jsonb)
to authenticated,service_role;

create or replace function public.unimis_applicant_register_document(
  p_application_id uuid,
  p_document_type text,
  p_file_name text,
  p_storage_path text,
  p_mime_type text default null,
  p_file_size_bytes bigint default null
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_inst uuid;
  v_id uuid;
begin
  if not public.unimis_applicant_owns_application(p_application_id) then
    raise exception 'You do not own this application.' using errcode='42501';
  end if;

  select institution_id into v_inst
  from public.applications where id=p_application_id;

  insert into public.application_documents(
    institution_id,application_id,document_type,file_name,storage_path,
    mime_type,file_size_bytes,verification_status
  )
  values(
    v_inst,p_application_id,trim(p_document_type),p_file_name,p_storage_path,
    p_mime_type,p_file_size_bytes,'pending'
  )
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function public.unimis_applicant_register_document(uuid,text,text,text,text,bigint)
to authenticated,service_role;

create or replace function public.unimis_applicant_respond_to_offer(
  p_offer_id uuid,
  p_response text,
  p_notes text default null
)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare
  v_offer public.admission_offers%rowtype;
begin
  if p_response not in ('accepted','declined') then
    raise exception 'Response must be accepted or declined.';
  end if;

  select o.* into v_offer
  from public.admission_offers o
  join public.applications ap on ap.id=o.application_id
  join public.applicants a on a.id=ap.applicant_id
  where o.id=p_offer_id and a.user_id=auth.uid()
  for update of o;

  if not found then raise exception 'Admission offer not found.'; end if;
  if v_offer.response_status<>'pending' then raise exception 'This offer has already been responded to.'; end if;

  if v_offer.expires_at is not null and now()>v_offer.expires_at then
    update public.admission_offers
    set response_status='expired',responded_at=now(),updated_at=now()
    where id=p_offer_id;
    raise exception 'Admission offer has expired.';
  end if;

  update public.admission_offers
  set response_status=p_response,
      responded_at=now(),
      accepted_at=case when p_response='accepted' then now() else null end,
      declined_at=case when p_response='declined' then now() else null end,
      acceptance_notes=nullif(trim(p_notes),''),
      updated_at=now()
  where id=p_offer_id;

  return true;
end;
$$;

grant execute on function public.unimis_applicant_respond_to_offer(uuid,text,text)
to authenticated,service_role;

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
      select jsonb_agg(to_jsonb(q) order by q.created_at desc)
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

drop policy if exists "Applicants can upload own admission documents" on storage.objects;
drop policy if exists "Applicants can read own admission documents" on storage.objects;
drop policy if exists "Applicants can delete own admission documents" on storage.objects;

create policy "Applicants can upload own admission documents"
on storage.objects for insert to authenticated
with check (
  bucket_id='admission-documents'
  and public.unimis_applicant_owns_application(nullif(split_part(name,'/',2),'')::uuid)
);

create policy "Applicants can read own admission documents"
on storage.objects for select to authenticated
using (
  bucket_id='admission-documents'
  and public.unimis_applicant_owns_application(nullif(split_part(name,'/',2),'')::uuid)
);

create policy "Applicants can delete own admission documents"
on storage.objects for delete to authenticated
using (
  bucket_id='admission-documents'
  and public.unimis_applicant_owns_application(nullif(split_part(name,'/',2),'')::uuid)
);

commit;

-- Verification:
-- select public.unimis_admissions_public_bootstrap();
-- select code,name,award_type,admission_level,accepts_local,accepts_international
-- from public.programmes order by name;
