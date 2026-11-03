begin;

-- Flexible grading assignments. Nothing here hard-codes Nursing, Medicine,
-- Engineering, Undergraduate or Postgraduate.
create table if not exists public.grading_scheme_assignments(
 id uuid primary key default gen_random_uuid(),
 institution_id uuid not null references public.institutions(id) on delete cascade,
 grading_scheme_id uuid not null references public.grading_schemes(id) on delete cascade,
 scope_type text not null check(scope_type in ('programme','course')),
 programme_id uuid references public.programmes(id) on delete cascade,
 course_id uuid references public.courses(id) on delete cascade,
 priority integer not null default 100,
 is_active boolean not null default true,
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check (
   (scope_type='programme' and programme_id is not null and course_id is null) or
   (scope_type='course' and course_id is not null and programme_id is null)
 )
);
create unique index if not exists uq_grading_assignment_programme
 on public.grading_scheme_assignments(institution_id,programme_id)
 where scope_type='programme' and is_active;
create unique index if not exists uq_grading_assignment_course
 on public.grading_scheme_assignments(institution_id,course_id)
 where scope_type='course' and is_active;

create or replace function public.unimis_grading_settings()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid;
begin
 select iu.institution_id into v_inst
 from public.institution_users iu
 where iu.user_id=auth.uid() and iu.status='active'
 order by iu.is_primary desc limit 1;
 if v_inst is null then raise exception 'Institution membership required'; end if;

 return jsonb_build_object(
  'schemes',coalesce((select jsonb_agg(jsonb_build_object(
    'id',gs.id,'name',gs.name,'code',gs.code,'gpa_scale',gs.gpa_scale,
    'is_default',gs.is_default,'status',gs.status,
    'bands',coalesce((select jsonb_agg(jsonb_build_object(
      'id',gb.id,'letter_grade',gb.letter_grade,'min_score',gb.min_score,
      'max_score',gb.max_score,'grade_point',gb.grade_point,
      'classification',gb.classification,'is_pass',gb.is_pass
    ) order by gb.min_score desc) from public.grade_bands gb where gb.grading_scheme_id=gs.id),'[]'::jsonb)
  ) order by gs.is_default desc,gs.name) from public.grading_schemes gs where gs.institution_id=v_inst),'[]'::jsonb),
  'programmes',coalesce((select jsonb_agg(jsonb_build_object(
     'id',p.id,'code',p.code,'name',p.name,
     'department_id',p.department_id,'level',p.level
   ) order by p.name) from public.programmes p where p.institution_id=v_inst),'[]'::jsonb),
  'courses',coalesce((select jsonb_agg(jsonb_build_object(
     'id',c.id,'code',c.code,'name',c.name
   ) order by c.code) from public.courses c where c.institution_id=v_inst),'[]'::jsonb),
  'assignments',coalesce((select jsonb_agg(jsonb_build_object(
    'id',a.id,'scope_type',a.scope_type,'programme_id',a.programme_id,'course_id',a.course_id,
    'grading_scheme_id',a.grading_scheme_id,'priority',a.priority,'is_active',a.is_active,
    'scheme_name',gs.name,'scheme_code',gs.code,
    'programme_code',p.code,'programme_name',p.name,'course_code',c.code,'course_name',c.name
  ) order by a.scope_type,coalesce(p.code,c.code))
  from public.grading_scheme_assignments a
  join public.grading_schemes gs on gs.id=a.grading_scheme_id
  left join public.programmes p on p.id=a.programme_id
  left join public.courses c on c.id=a.course_id
  where a.institution_id=v_inst and a.is_active),'[]'::jsonb)
 );
end $$;

create or replace function public.unimis_save_grading_assignment(p_assignment jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid; v_scope text; v_scheme uuid; v_programme uuid; v_course uuid; v_id uuid;
begin
 select iu.institution_id into v_inst
 from public.institution_users iu join public.roles r on r.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active' and r.code in ('owner','admin','exam_officer')
 order by iu.is_primary desc limit 1;
 if v_inst is null then raise exception 'Academic administration access required'; end if;

 v_scope:=p_assignment->>'scope_type';
 v_scheme:=(p_assignment->>'grading_scheme_id')::uuid;
 v_programme:=nullif(p_assignment->>'programme_id','')::uuid;
 v_course:=nullif(p_assignment->>'course_id','')::uuid;

 if not exists(select 1 from public.grading_schemes where id=v_scheme and institution_id=v_inst) then
   raise exception 'Invalid grading scheme';
 end if;

 if v_scope='programme' then
   if v_programme is null then raise exception 'Programme is required'; end if;
   update public.grading_scheme_assignments set is_active=false,updated_at=now()
    where institution_id=v_inst and scope_type='programme' and programme_id=v_programme and is_active;
   insert into public.grading_scheme_assignments(institution_id,grading_scheme_id,scope_type,programme_id,created_by)
   values(v_inst,v_scheme,'programme',v_programme,auth.uid()) returning id into v_id;
 elsif v_scope='course' then
   if v_course is null then raise exception 'Course is required'; end if;
   update public.grading_scheme_assignments set is_active=false,updated_at=now()
    where institution_id=v_inst and scope_type='course' and course_id=v_course and is_active;
   insert into public.grading_scheme_assignments(institution_id,grading_scheme_id,scope_type,course_id,created_by)
   values(v_inst,v_scheme,'course',v_course,auth.uid()) returning id into v_id;
 else
   raise exception 'scope_type must be programme or course';
 end if;
 return jsonb_build_object('ok',true,'id',v_id);
end $$;

create or replace function public.unimis_delete_grading_assignment(p_assignment_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid;
begin
 select iu.institution_id into v_inst
 from public.institution_users iu join public.roles r on r.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active' and r.code in ('owner','admin','exam_officer')
 order by iu.is_primary desc limit 1;
 if v_inst is null then raise exception 'Academic administration access required'; end if;
 update public.grading_scheme_assignments set is_active=false,updated_at=now()
 where id=p_assignment_id and institution_id=v_inst;
 return jsonb_build_object('ok',true);
end $$;

-- Central resolver:
-- 1 course override, 2 programme assignment, 3 institution default.
create or replace function public.unimis_resolve_grading_scheme(
 p_course_offering_id uuid,
 p_student_id uuid default null
) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_inst uuid; v_course uuid; v_programme uuid; v_scheme uuid;
begin
 select co.institution_id,co.course_id into v_inst,v_course
 from public.course_offerings co where co.id=p_course_offering_id;
 if v_inst is null then raise exception 'Course offering not found'; end if;

 if p_student_id is not null then
   select spe.programme_id into v_programme
   from public.student_programme_enrolments spe
   where spe.student_id=p_student_id and spe.is_primary=true
   order by spe.created_at desc limit 1;
 end if;

 select a.grading_scheme_id into v_scheme
 from public.grading_scheme_assignments a
 where a.institution_id=v_inst and a.is_active and a.scope_type='course' and a.course_id=v_course
 order by a.priority desc,a.updated_at desc limit 1;
 if v_scheme is not null then return v_scheme; end if;

 if v_programme is not null then
   select a.grading_scheme_id into v_scheme
   from public.grading_scheme_assignments a
   where a.institution_id=v_inst and a.is_active and a.scope_type='programme' and a.programme_id=v_programme
   order by a.priority desc,a.updated_at desc limit 1;
   if v_scheme is not null then return v_scheme; end if;
 end if;

 select gs.id into v_scheme from public.grading_schemes gs
 where gs.institution_id=v_inst and gs.is_default=true and gs.status='active'
 order by gs.updated_at desc nulls last,gs.created_at desc limit 1;
 if v_scheme is null then raise exception 'No applicable grading scheme is configured'; end if;
 return v_scheme;
end $$;

-- Human-readable diagnostic so administrators can verify why a scheme was selected.
create or replace function public.unimis_explain_grading_resolution(
 p_course_offering_id uuid,p_student_id uuid
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_scheme uuid; v_programme uuid; v_course uuid; v_inst uuid; v_source text:='institution_default'; r record;
begin
 select co.institution_id,co.course_id into v_inst,v_course from public.course_offerings co where co.id=p_course_offering_id;
 select spe.programme_id into v_programme from public.student_programme_enrolments spe
 where spe.student_id=p_student_id and spe.is_primary=true order by spe.created_at desc limit 1;

 select a.grading_scheme_id into v_scheme from public.grading_scheme_assignments a
 where a.institution_id=v_inst and a.is_active and a.scope_type='course' and a.course_id=v_course limit 1;
 if v_scheme is not null then v_source:='course_override';
 else
   select a.grading_scheme_id into v_scheme from public.grading_scheme_assignments a
   where a.institution_id=v_inst and a.is_active and a.scope_type='programme' and a.programme_id=v_programme limit 1;
   if v_scheme is not null then v_source:='programme';
   else select id into v_scheme from public.grading_schemes where institution_id=v_inst and is_default and status='active' limit 1;
   end if;
 end if;
 select id,name,code,gpa_scale into r from public.grading_schemes where id=v_scheme;
 return jsonb_build_object('scheme_id',r.id,'scheme_name',r.name,'scheme_code',r.code,'gpa_scale',r.gpa_scale,'source',v_source);
end $$;

grant execute on function public.unimis_grading_settings() to authenticated;
grant execute on function public.unimis_save_grading_assignment(jsonb) to authenticated;
grant execute on function public.unimis_delete_grading_assignment(uuid) to authenticated;
grant execute on function public.unimis_resolve_grading_scheme(uuid,uuid) to authenticated;
grant execute on function public.unimis_explain_grading_resolution(uuid,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
