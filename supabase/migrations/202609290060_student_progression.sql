
begin;

create table if not exists public.academic_progression_rules(
 id uuid primary key default gen_random_uuid(),
 institution_id uuid not null,
 programme_id uuid,
 from_level integer not null,
 to_level integer not null,
 min_credits_earned numeric(8,2) not null default 0,
 max_failed_credits numeric(8,2) not null default 0,
 min_cgpa numeric(5,2),
 allow_carry_over boolean not null default true,
 is_active boolean not null default true,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create unique index if not exists uq_progression_rule on public.academic_progression_rules(institution_id,coalesce(programme_id,'00000000-0000-0000-0000-000000000000'::uuid),from_level) where is_active;

create table if not exists public.student_progression_reviews(
 id uuid primary key default gen_random_uuid(),
 institution_id uuid not null,
 academic_year_id uuid not null,
 student_id uuid not null,
 programme_enrolment_id uuid not null,
 programme_id uuid not null,
 from_level integer not null,
 proposed_level integer,
 decision text not null check(decision in('eligible','carry_over','manual_review','repeat','probation','deferred','withdrawn','promoted')),
 credits_registered numeric(8,2) not null default 0,
 credits_earned numeric(8,2) not null default 0,
 failed_credits numeric(8,2) not null default 0,
 courses_failed integer not null default 0,
 cgpa numeric(6,3),
 reasons jsonb not null default '[]'::jsonb,
 failed_courses jsonb not null default '[]'::jsonb,
 evaluated_at timestamptz not null default now(),
 promoted_at timestamptz,
 promoted_by uuid,
 override_reason text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(academic_year_id,student_id,programme_enrolment_id)
);

create table if not exists public.student_progression_history(
 id uuid primary key default gen_random_uuid(),
 institution_id uuid not null,
 student_id uuid not null,
 academic_year_id uuid not null,
 programme_enrolment_id uuid not null,
 from_level integer not null,
 to_level integer,
 action text not null,
 system_decision text,
 reasons jsonb not null default '[]'::jsonb,
 notes text,
 acted_by uuid,
 acted_at timestamptz not null default now()
);

alter table public.academic_progression_rules enable row level security;
alter table public.student_progression_reviews enable row level security;
alter table public.student_progression_history enable row level security;

create or replace function public.unimis_progression_access()
returns uuid language sql stable security definer set search_path='' as $$
 select iu.institution_id from public.institution_users iu
 join public.roles r on r.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active'
 and lower(coalesce(r.code,r.name)) in ('admin','administrator','owner','registrar','superadmin','super_admin','exams_officer','examination_officer','examinations_officer')
 limit 1
$$;

create or replace function public.unimis_progression_evaluate(p_academic_year_id uuid,p_programme_id uuid default null,p_level integer default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid; v_count int:=0; rec record; v_rule record; v_registered numeric; v_earned numeric; v_failed numeric; v_failed_count int; v_cgpa numeric; v_failed_courses jsonb; v_decision text; v_reasons jsonb;
begin
 v_inst:=public.unimis_progression_access(); if v_inst is null then raise exception 'Progression access required'; end if;
 for rec in
  select s.id student_id,s.student_number,s.first_name,s.last_name,e.id enrolment_id,e.programme_id,e.current_level
  from public.students s join public.student_programme_enrolments e on e.student_id=s.id and e.is_primary=true
  where s.institution_id=v_inst and e.enrolment_status='active'
   and (p_programme_id is null or e.programme_id=p_programme_id)
   and (p_level is null or e.current_level=p_level)
 loop
  select * into v_rule from public.academic_progression_rules r
   where r.institution_id=v_inst and r.is_active and r.from_level=rec.current_level
    and (r.programme_id=rec.programme_id or r.programme_id is null)
   order by (r.programme_id is not null) desc limit 1;
  if v_rule.id is null then
   v_reasons:=jsonb_build_array('No active progression rule configured for this programme/level');
   v_decision:='manual_review'; v_registered:=0;v_earned:=0;v_failed:=0;v_failed_count:=0;v_cgpa:=null;v_failed_courses:='[]'::jsonb;
  else
   select coalesce(sum(c.credit_hours),0),
          coalesce(sum(c.credit_hours) filter(where cr.passed=true and cr.result_status='published'),0),
          coalesce(sum(c.credit_hours) filter(where coalesce(cr.passed,false)=false and cr.result_status='published'),0),
          count(*) filter(where coalesce(cr.passed,false)=false and cr.result_status='published'),
          case when sum(c.credit_hours) filter(where cr.result_status='published')>0
               then round(sum(coalesce(cr.grade_point,0)*c.credit_hours) filter(where cr.result_status='published')/sum(c.credit_hours) filter(where cr.result_status='published'),3) end,
          coalesce(jsonb_agg(jsonb_build_object('course_code',c.code,'course_name',c.name,'credits',c.credit_hours,'score',cr.total_score,'grade',cr.letter_grade))
             filter(where coalesce(cr.passed,false)=false and cr.result_status='published'),'[]'::jsonb)
    into v_registered,v_earned,v_failed,v_failed_count,v_cgpa,v_failed_courses
   from public.student_course_registrations scr
   join public.course_offerings co on co.id=scr.course_offering_id
   join public.academic_periods ap on ap.id=co.academic_period_id
   join public.courses c on c.id=co.course_id
   left join public.course_results cr on cr.student_course_registration_id=scr.id
   where scr.student_id=rec.student_id and ap.academic_year_id=p_academic_year_id and scr.status<>'dropped';

   v_reasons:='[]'::jsonb;
   if v_registered=0 then v_reasons:=v_reasons||jsonb_build_array('No registered courses found for the academic year'); end if;
   if v_earned<v_rule.min_credits_earned then v_reasons:=v_reasons||jsonb_build_array(format('Credits earned %s below required %s',v_earned,v_rule.min_credits_earned)); end if;
   if v_failed>v_rule.max_failed_credits then v_reasons:=v_reasons||jsonb_build_array(format('Failed credits %s exceed allowed %s',v_failed,v_rule.max_failed_credits)); end if;
   if v_rule.min_cgpa is not null and coalesce(v_cgpa,0)<v_rule.min_cgpa then v_reasons:=v_reasons||jsonb_build_array(format('CGPA %s below required %s',coalesce(v_cgpa,0),v_rule.min_cgpa)); end if;
   if v_registered=0 then v_decision:='manual_review';
   elsif jsonb_array_length(v_reasons)=0 and v_failed>0 and v_rule.allow_carry_over then v_decision:='carry_over';
   elsif jsonb_array_length(v_reasons)=0 then v_decision:='eligible';
   else v_decision:='manual_review'; end if;
  end if;
  insert into public.student_progression_reviews(institution_id,academic_year_id,student_id,programme_enrolment_id,programme_id,from_level,proposed_level,decision,credits_registered,credits_earned,failed_credits,courses_failed,cgpa,reasons,failed_courses,evaluated_at,updated_at)
  values(v_inst,p_academic_year_id,rec.student_id,rec.enrolment_id,rec.programme_id,rec.current_level,coalesce(v_rule.to_level,rec.current_level),v_decision,v_registered,v_earned,v_failed,v_failed_count,v_cgpa,v_reasons,v_failed_courses,now(),now())
  on conflict(academic_year_id,student_id,programme_enrolment_id) do update set proposed_level=excluded.proposed_level,decision=excluded.decision,credits_registered=excluded.credits_registered,credits_earned=excluded.credits_earned,failed_credits=excluded.failed_credits,courses_failed=excluded.courses_failed,cgpa=excluded.cgpa,reasons=excluded.reasons,failed_courses=excluded.failed_courses,evaluated_at=now(),updated_at=now();
  v_count:=v_count+1;
 end loop;
 return jsonb_build_object('evaluated',v_count);
end $$;

create or replace function public.unimis_progression_queue(p_academic_year_id uuid default null,p_programme_id uuid default null,p_level integer default null,p_decision text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid;
begin
 v_inst:=public.unimis_progression_access(); if v_inst is null then raise exception 'Progression access required'; end if;
 return jsonb_build_object(
  'summary',(select jsonb_build_object('total',count(*),'eligible',count(*) filter(where r.decision in('eligible','carry_over')),'exceptions',count(*) filter(where r.decision='manual_review'),'promoted',count(*) filter(where r.decision='promoted')) from public.student_progression_reviews r where r.institution_id=v_inst and (p_academic_year_id is null or r.academic_year_id=p_academic_year_id) and (p_programme_id is null or r.programme_id=p_programme_id) and (p_level is null or r.from_level=p_level)),
  'rows',coalesce((select jsonb_agg(to_jsonb(x) order by x.student_number) from (
   select r.id review_id,r.student_id,s.student_number,s.first_name,s.middle_name,s.last_name,p.code programme_code,p.name programme_name,r.from_level,r.proposed_level,r.decision,r.credits_registered,r.credits_earned,r.failed_credits,r.courses_failed,r.cgpa,r.reasons,r.failed_courses,r.evaluated_at,r.promoted_at
   from public.student_progression_reviews r join public.students s on s.id=r.student_id join public.programmes p on p.id=r.programme_id
   where r.institution_id=v_inst and (p_academic_year_id is null or r.academic_year_id=p_academic_year_id) and (p_programme_id is null or r.programme_id=p_programme_id) and (p_level is null or r.from_level=p_level) and (p_decision is null or p_decision='' or r.decision=p_decision)
  ) x),'[]'::jsonb)
 );
end $$;

create or replace function public.unimis_progression_bulk_promote(p_review_ids uuid[])
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid; r record; n int:=0;
begin
 v_inst:=public.unimis_progression_access(); if v_inst is null then raise exception 'Progression access required'; end if;
 for r in select * from public.student_progression_reviews where institution_id=v_inst and id=any(p_review_ids) and decision in('eligible','carry_over')
 loop
  update public.student_programme_enrolments set current_level=r.proposed_level,updated_at=now() where id=r.programme_enrolment_id;
  update public.student_progression_reviews set decision='promoted',promoted_at=now(),promoted_by=auth.uid(),updated_at=now() where id=r.id;
  insert into public.student_progression_history(institution_id,student_id,academic_year_id,programme_enrolment_id,from_level,to_level,action,system_decision,reasons,acted_by)
  values(v_inst,r.student_id,r.academic_year_id,r.programme_enrolment_id,r.from_level,r.proposed_level,'bulk_promoted',r.decision,r.reasons,auth.uid());
  n:=n+1;
 end loop;
 return jsonb_build_object('promoted',n);
end $$;

create or replace function public.unimis_progression_override(p_review_id uuid,p_decision text,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid; r record; v_to int;
begin
 v_inst:=public.unimis_progression_access(); if v_inst is null then raise exception 'Progression access required'; end if;
 if nullif(trim(p_reason),'') is null then raise exception 'Override reason is required'; end if;
 select * into r from public.student_progression_reviews where id=p_review_id and institution_id=v_inst;
 if r.id is null then raise exception 'Progression review not found'; end if;
 v_to:=case when p_decision='promoted' then r.proposed_level else r.from_level end;
 if p_decision='promoted' then update public.student_programme_enrolments set current_level=r.proposed_level,updated_at=now() where id=r.programme_enrolment_id; end if;
 update public.student_progression_reviews set decision=p_decision,override_reason=p_reason,promoted_at=case when p_decision='promoted' then now() else promoted_at end,promoted_by=case when p_decision='promoted' then auth.uid() else promoted_by end,updated_at=now() where id=r.id;
 insert into public.student_progression_history(institution_id,student_id,academic_year_id,programme_enrolment_id,from_level,to_level,action,system_decision,reasons,notes,acted_by)
 values(v_inst,r.student_id,r.academic_year_id,r.programme_enrolment_id,r.from_level,v_to,'manual_override',r.decision,r.reasons,p_reason,auth.uid());
 return jsonb_build_object('ok',true,'decision',p_decision);
end $$;

revoke all on function public.unimis_progression_access() from public;
grant execute on function public.unimis_progression_evaluate(uuid,uuid,integer) to authenticated;
grant execute on function public.unimis_progression_queue(uuid,uuid,integer,text) to authenticated;
grant execute on function public.unimis_progression_bulk_promote(uuid[]) to authenticated;
grant execute on function public.unimis_progression_override(uuid,text,text) to authenticated;
commit;
