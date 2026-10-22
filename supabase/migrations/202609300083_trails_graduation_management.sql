begin;

create table if not exists public.student_academic_trails(
 id uuid primary key default gen_random_uuid(), institution_id uuid not null references public.institutions(id) on delete cascade,
 student_id uuid not null references public.students(id) on delete cascade, programme_id uuid references public.programmes(id) on delete set null,
 course_id uuid not null references public.courses(id) on delete restrict, source_course_result_id uuid references public.course_results(id) on delete set null,
 source_academic_year_id uuid references public.academic_years(id) on delete set null, credits numeric(8,2) not null default 0,
 failed_score numeric(6,2), failed_grade text, status text not null default 'outstanding' check(status in('outstanding','registered','cleared','waived')),
 cleared_course_result_id uuid references public.course_results(id) on delete set null, cleared_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(student_id,course_id,source_course_result_id)
);
create index if not exists idx_student_trails_lookup on public.student_academic_trails(institution_id,student_id,status);

create table if not exists public.graduation_reviews(
 id uuid primary key default gen_random_uuid(), institution_id uuid not null references public.institutions(id) on delete cascade,
 academic_year_id uuid not null references public.academic_years(id) on delete restrict, student_id uuid not null references public.students(id) on delete cascade,
 programme_enrolment_id uuid not null references public.student_programme_enrolments(id) on delete cascade, programme_id uuid not null references public.programmes(id) on delete restrict,
 final_level integer not null, credits_required numeric(8,2), credits_earned numeric(8,2) not null default 0, cgpa numeric(6,3), outstanding_trails integer not null default 0,
 decision text not null check(decision in('eligible','completion_exception','approved','graduated','withheld')),
 reasons jsonb not null default '[]'::jsonb, evaluated_at timestamptz not null default now(), approved_at timestamptz, approved_by uuid, graduated_at timestamptz, graduation_date date,
 notes text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(academic_year_id,student_id,programme_enrolment_id)
);

alter table public.student_academic_trails enable row level security;
alter table public.graduation_reviews enable row level security;
grant select,insert,update on public.student_academic_trails,public.graduation_reviews to authenticated;

create or replace function public.unimis_sync_academic_trails(p_academic_year_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid; v_added int:=0; v_cleared int:=0;
begin
 v_inst:=public.unimis_progression_access(); if v_inst is null then raise exception 'Academic records access required'; end if;
 insert into public.student_academic_trails(institution_id,student_id,programme_id,course_id,source_course_result_id,source_academic_year_id,credits,failed_score,failed_grade,status)
 select v_inst,cr.student_id,spe.programme_id,co.course_id,cr.id,ap.academic_year_id,c.credit_hours,cr.total_score,cr.letter_grade,'outstanding'
 from public.course_results cr join public.course_offerings co on co.id=cr.course_offering_id join public.academic_periods ap on ap.id=co.academic_period_id
 join public.courses c on c.id=co.course_id left join public.student_programme_enrolments spe on spe.student_id=cr.student_id and spe.is_primary=true
 where cr.institution_id=v_inst and cr.result_status='published' and coalesce(cr.passed,false)=false and (p_academic_year_id is null or ap.academic_year_id=p_academic_year_id)
 on conflict(student_id,course_id,source_course_result_id) do nothing;
 get diagnostics v_added=row_count;
 with clearable as (
   select t.id trail_id,q.result_id,q.published_at from public.student_academic_trails t
   join lateral (select cr2.id result_id,cr2.published_at from public.course_results cr2 join public.course_offerings co2 on co2.id=cr2.course_offering_id where cr2.student_id=t.student_id and co2.course_id=t.course_id and cr2.result_status='published' and cr2.passed=true and cr2.published_at is not null and cr2.published_at>coalesce((select published_at from public.course_results where id=t.source_course_result_id),t.created_at) order by cr2.published_at desc limit 1) q on true
   where t.institution_id=v_inst and t.status in('outstanding','registered')
  )
 update public.student_academic_trails t set status='cleared',cleared_course_result_id=c.result_id,cleared_at=c.published_at,updated_at=now() from clearable c where t.id=c.trail_id;
 get diagnostics v_cleared=row_count;
 return jsonb_build_object('added',v_added,'cleared',v_cleared);
end $$;

create or replace function public.unimis_trail_students(p_programme_id uuid default null,p_level integer default null,p_status text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid;
begin
 v_inst:=public.unimis_progression_access(); if v_inst is null then raise exception 'Academic records access required'; end if;
 perform public.unimis_sync_academic_trails(null);
 return jsonb_build_object('summary',jsonb_build_object(
  'students',(select count(distinct t.student_id) from public.student_academic_trails t where t.institution_id=v_inst and t.status in('outstanding','registered')),
  'courses',(select count(*) from public.student_academic_trails t where t.institution_id=v_inst and t.status in('outstanding','registered')),
  'credits',(select coalesce(sum(t.credits),0) from public.student_academic_trails t where t.institution_id=v_inst and t.status in('outstanding','registered'))),
 'rows',coalesce((select jsonb_agg(to_jsonb(x) order by x.student_number,x.course_code) from (
  select t.id trail_id,t.student_id,s.student_number,s.first_name,s.middle_name,s.last_name,p.id programme_id,p.code programme_code,p.name programme_name,spe.current_level,c.code course_code,c.name course_name,t.credits,t.failed_score,t.failed_grade,t.status,ay.name academic_year,t.created_at,t.cleared_at
  from public.student_academic_trails t join public.students s on s.id=t.student_id join public.courses c on c.id=t.course_id left join public.programmes p on p.id=t.programme_id
  left join public.student_programme_enrolments spe on spe.student_id=t.student_id and spe.is_primary=true left join public.academic_years ay on ay.id=t.source_academic_year_id
  where t.institution_id=v_inst and (p_programme_id is null or t.programme_id=p_programme_id) and (p_level is null or spe.current_level=p_level) and (p_status is null or p_status='' or t.status=p_status)
 )x),'[]'::jsonb));
end $$;

create or replace function public.unimis_evaluate_graduation(p_academic_year_id uuid,p_programme_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid; rec record; v_final int; v_earned numeric; v_cgpa numeric; v_trails int; v_required numeric; v_reasons jsonb; v_decision text; n int:=0;
begin
 v_inst:=public.unimis_progression_access(); if v_inst is null then raise exception 'Graduation access required'; end if;
 perform public.unimis_sync_academic_trails(null);
 for rec in select s.id student_id,e.id enrolment_id,e.programme_id,e.current_level,p.duration_years,p.total_credits from public.students s join public.student_programme_enrolments e on e.student_id=s.id and e.is_primary=true join public.programmes p on p.id=e.programme_id where s.institution_id=v_inst and e.enrolment_status='active' and (p_programme_id is null or e.programme_id=p_programme_id)
 loop
  v_final:=greatest(100,round(coalesce(rec.duration_years,rec.current_level/100.0))::int*100); if rec.current_level<v_final then continue; end if;
  v_required:=rec.total_credits;
  select coalesce(sum(z.credit_hours),0),case when sum(z.credit_hours)>0 then round(sum(z.grade_point*z.credit_hours)/sum(z.credit_hours),3) end into v_earned,v_cgpa from (
    select distinct on(co.course_id) co.course_id,c.credit_hours,cr.grade_point from public.course_results cr join public.course_offerings co on co.id=cr.course_offering_id join public.courses c on c.id=co.course_id where cr.student_id=rec.student_id and cr.result_status='published' and cr.passed=true order by co.course_id,cr.published_at desc nulls last
  )z;
  select count(*) into v_trails from public.student_academic_trails where student_id=rec.student_id and status in('outstanding','registered');
  v_reasons:='[]'::jsonb;
  if v_required is null or v_required<=0 then v_reasons:=v_reasons||jsonb_build_array('Programme total credits are not configured');
  elsif v_earned<v_required then v_reasons:=v_reasons||jsonb_build_array(format('Credits earned %s below programme requirement %s',v_earned,v_required)); end if;
  if v_trails>0 then v_reasons:=v_reasons||jsonb_build_array(format('%s outstanding trail course(s)',v_trails)); end if;
  v_decision:=case when jsonb_array_length(v_reasons)=0 then 'eligible' else 'completion_exception' end;
  insert into public.graduation_reviews(institution_id,academic_year_id,student_id,programme_enrolment_id,programme_id,final_level,credits_required,credits_earned,cgpa,outstanding_trails,decision,reasons,evaluated_at,updated_at)
  values(v_inst,p_academic_year_id,rec.student_id,rec.enrolment_id,rec.programme_id,v_final,v_required,v_earned,v_cgpa,v_trails,v_decision,v_reasons,now(),now())
  on conflict(academic_year_id,student_id,programme_enrolment_id) do update set final_level=excluded.final_level,credits_required=excluded.credits_required,credits_earned=excluded.credits_earned,cgpa=excluded.cgpa,outstanding_trails=excluded.outstanding_trails,decision=case when graduation_reviews.decision in('approved','graduated') then graduation_reviews.decision else excluded.decision end,reasons=excluded.reasons,evaluated_at=now(),updated_at=now(); n:=n+1;
 end loop;
 return jsonb_build_object('evaluated',n);
end $$;

create or replace function public.unimis_graduation_queue(p_academic_year_id uuid default null,p_programme_id uuid default null,p_decision text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid;
begin
 v_inst:=public.unimis_progression_access(); if v_inst is null then raise exception 'Graduation access required'; end if;
 return jsonb_build_object('summary',(select jsonb_build_object('total',count(*),'eligible',count(*) filter(where decision='eligible'),'exceptions',count(*) filter(where decision='completion_exception'),'approved',count(*) filter(where decision='approved'),'graduated',count(*) filter(where decision='graduated')) from public.graduation_reviews where institution_id=v_inst and (p_academic_year_id is null or academic_year_id=p_academic_year_id) and (p_programme_id is null or programme_id=p_programme_id)),
 'rows',coalesce((select jsonb_agg(to_jsonb(x) order by x.student_number) from (select g.id review_id,g.student_id,s.student_number,s.first_name,s.middle_name,s.last_name,p.code programme_code,p.name programme_name,p.award_type,g.final_level,g.credits_required,g.credits_earned,g.cgpa,g.outstanding_trails,g.decision,g.reasons,g.evaluated_at,g.approved_at,g.graduation_date from public.graduation_reviews g join public.students s on s.id=g.student_id join public.programmes p on p.id=g.programme_id where g.institution_id=v_inst and (p_academic_year_id is null or g.academic_year_id=p_academic_year_id) and (p_programme_id is null or g.programme_id=p_programme_id) and (p_decision is null or p_decision='' or g.decision=p_decision))x),'[]'::jsonb));
end $$;

create or replace function public.unimis_approve_graduation(p_review_ids uuid[])
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid; r record; n int:=0;
begin
 v_inst:=public.unimis_progression_access(); if v_inst is null then raise exception 'Graduation access required'; end if;
 for r in select * from public.graduation_reviews where institution_id=v_inst and id=any(p_review_ids) and decision='eligible' loop
  update public.graduation_reviews set decision='approved',approved_at=now(),approved_by=auth.uid(),updated_at=now() where id=r.id; n:=n+1;
 end loop; return jsonb_build_object('approved',n);
end $$;

create or replace function public.unimis_mark_graduated(p_review_ids uuid[],p_graduation_date date default current_date)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid; r record; n int:=0;
begin
 v_inst:=public.unimis_progression_access(); if v_inst is null then raise exception 'Graduation access required'; end if;
 for r in select * from public.graduation_reviews where institution_id=v_inst and id=any(p_review_ids) and decision='approved' loop
  update public.graduation_reviews set decision='graduated',graduated_at=now(),graduation_date=p_graduation_date,updated_at=now() where id=r.id;
  update public.student_programme_enrolments set enrolment_status='completed',updated_at=now() where id=r.programme_enrolment_id;
  update public.students set status='graduated',updated_at=now() where id=r.student_id; n:=n+1;
 end loop; return jsonb_build_object('graduated',n);
end $$;

grant execute on function public.unimis_sync_academic_trails(uuid),public.unimis_trail_students(uuid,integer,text),public.unimis_evaluate_graduation(uuid,uuid),public.unimis_graduation_queue(uuid,uuid,text),public.unimis_approve_graduation(uuid[]),public.unimis_mark_graduated(uuid[],date) to authenticated;
commit;
