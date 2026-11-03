
-- UniMIS Lecturer Portal Phase 1
-- Connects an authenticated lecturer to existing lecturer_profiles,
-- course_lecturers, course_offerings and course_schedules.
-- Also creates a LOCAL DEMO LOGIN for the existing Kwame Mensah lecturer.
begin;

create or replace function public.unimis_lecturer_workspace()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_inst uuid;
  v_staff_number text;
  v_staff_id uuid;
  v_lecturer_id uuid;
  v_result jsonb;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;

  select iu.institution_id, iu.staff_number
    into v_inst, v_staff_number
  from public.institution_users iu
  join public.roles r on r.id=iu.role_id
  where iu.user_id=v_uid
    and iu.status='active'
    and r.code='lecturer'
  order by iu.is_primary desc nulls last, iu.joined_at
  limit 1;

  if v_inst is null then raise exception 'Active lecturer membership not found'; end if;

  select s.id into v_staff_id
  from public.staff s
  where s.institution_id=v_inst
    and (
      (v_staff_number is not null and s.staff_number=v_staff_number)
      or lower(s.email)=lower(coalesce((select email from auth.users where id=v_uid),''))
    )
  order by case when s.staff_number=v_staff_number then 0 else 1 end
  limit 1;

  if v_staff_id is null then raise exception 'Lecturer staff record not linked to this login'; end if;

  select lp.id into v_lecturer_id
  from public.lecturer_profiles lp
  where lp.institution_id=v_inst and lp.staff_id=v_staff_id and lp.is_active=true
  limit 1;

  if v_lecturer_id is null then raise exception 'Active lecturer profile not found'; end if;

  select jsonb_build_object(
    'lecturer', jsonb_build_object(
      'lecturer_profile_id',lp.id,'staff_id',s.id,'staff_number',s.staff_number,
      'first_name',s.first_name,'middle_name',s.middle_name,'last_name',s.last_name,
      'email',s.email,'job_title',s.job_title,'academic_rank',lp.academic_rank,
      'specialization',lp.specialization
    ),
    'courses', coalesce((
      select jsonb_agg(jsonb_build_object(
        'allocation_id',cl.id,
        'allocation_role',cl.role,
        'is_primary',cl.is_primary,
        'course_offering_id',co.id,
        'course_code',c.code,
        'course_name',c.name,
        'credit_hours',c.credit_hours,
        'section_code',co.section_code,
        'level_number',co.level_number,
        'offering_status',co.status,
        'registration_open',co.registration_open,
        'programme_code',p.code,
        'programme_name',p.name,
        'academic_year',ay.name,
        'academic_period',ap.name,
        'academic_period_id',ap.id
      ) order by ay.start_date desc, ap.period_number, c.code)
      from public.course_lecturers cl
      join public.course_offerings co on co.id=cl.course_offering_id
      join public.courses c on c.id=co.course_id
      left join public.programmes p on p.id=co.programme_id
      left join public.academic_years ay on ay.id=co.academic_year_id
      left join public.academic_periods ap on ap.id=co.academic_period_id
      where cl.institution_id=v_inst and cl.lecturer_profile_id=v_lecturer_id
    ),'[]'::jsonb),
    'schedule', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',cs.id,'course_offering_id',cs.course_offering_id,
        'day_of_week',cs.day_of_week,'start_time',cs.start_time,'end_time',cs.end_time,
        'venue',cs.venue,'schedule_type',cs.schedule_type,
        'course_code',c.code,'course_name',c.name,'section_code',co.section_code,
        'programme_code',p.code,'academic_period',ap.name
      ) order by cs.day_of_week,cs.start_time)
      from public.course_schedules cs
      join public.course_offerings co on co.id=cs.course_offering_id
      join public.course_lecturers cl on cl.course_offering_id=co.id
        and cl.lecturer_profile_id=v_lecturer_id
      join public.courses c on c.id=co.course_id
      left join public.programmes p on p.id=co.programme_id
      left join public.academic_periods ap on ap.id=co.academic_period_id
      where cs.institution_id=v_inst
    ),'[]'::jsonb)
  )
  into v_result
  from public.lecturer_profiles lp
  join public.staff s on s.id=lp.staff_id
  where lp.id=v_lecturer_id;

  return v_result;
end $$;

revoke all on function public.unimis_lecturer_workspace() from public;
grant execute on function public.unimis_lecturer_workspace() to authenticated;

-- LOCAL DEMO LECTURER LOGIN.
-- Link the login to the existing Kwame Mensah staff/lecturer record already visible
-- in Lecturer Allocation. Password is for local/demo use only.
do $$
declare
  v_staff public.staff%rowtype;
  v_role_id uuid;
  v_user_id uuid;
  v_email text := 'kwame.mensah@unimis.local';
  v_password text := 'Lecturer@2026';
begin
  select s.* into v_staff
  from public.staff s
  join public.lecturer_profiles lp on lp.staff_id=s.id and lp.is_active=true
  where lower(coalesce(s.first_name,''))='kwame'
    and lower(coalesce(s.last_name,''))='mensah'
  order by s.created_at
  limit 1;

  if v_staff.id is null then
    raise notice 'Kwame Mensah lecturer record not found; demo login seed skipped.';
    return;
  end if;

  select id into v_role_id from public.roles where code='lecturer' limit 1;
  if v_role_id is null then raise exception 'Lecturer role is missing'; end if;

  select id into v_user_id from auth.users where lower(email)=lower(v_email) limit 1;

  if v_user_id is null then
    v_user_id := gen_random_uuid();
    insert into auth.users(
      instance_id,id,aud,role,email,encrypted_password,
      email_confirmed_at,created_at,updated_at,
      raw_app_meta_data,raw_user_meta_data,is_super_admin
    ) values (
      '00000000-0000-0000-0000-000000000000',v_user_id,'authenticated','authenticated',
      v_email,crypt(v_password,gen_salt('bf')),now(),now(),now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object('first_name',v_staff.first_name,'last_name',v_staff.last_name),
      false
    );

    insert into auth.identities(
      id,user_id,provider_id,identity_data,provider,last_sign_in_at,created_at,updated_at
    ) values (
      gen_random_uuid(),v_user_id,v_user_id::text,
      jsonb_build_object('sub',v_user_id::text,'email',v_email,'email_verified',true),
      'email',now(),now(),now()
    );
  else
    update auth.users
       set encrypted_password=crypt(v_password,gen_salt('bf')),
           email_confirmed_at=coalesce(email_confirmed_at,now()),
           updated_at=now()
     where id=v_user_id;
  end if;

  -- Profile is used by common UniMIS identity/header components.
  insert into public.profiles(id,email,first_name,last_name)
  values(v_user_id,v_email,v_staff.first_name,v_staff.last_name)
  on conflict(id) do update set
    email=excluded.email,
    first_name=excluded.first_name,
    last_name=excluded.last_name;

  if not exists (
    select 1 from public.institution_users
    where institution_id=v_staff.institution_id and user_id=v_user_id and role_id=v_role_id
  ) then
    insert into public.institution_users(
      institution_id,user_id,role_id,staff_number,status,is_primary,joined_at
    ) values (
      v_staff.institution_id,v_user_id,v_role_id,v_staff.staff_number,'active',true,now()
    );
  else
    update public.institution_users
       set staff_number=v_staff.staff_number,status='active',is_primary=true
     where institution_id=v_staff.institution_id and user_id=v_user_id and role_id=v_role_id;
  end if;
end $$;

commit;
