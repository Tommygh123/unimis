begin;

create table if not exists public.degree_classification_schemes(
 id uuid primary key default gen_random_uuid(),
 institution_id uuid not null references public.institutions(id) on delete cascade,
 name text not null,
 code text not null,
 gpa_scale numeric(5,2) not null default 4.00,
 is_default boolean not null default false,
 active boolean not null default true,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(institution_id,code)
);
create table if not exists public.degree_classification_bands(
 id uuid primary key default gen_random_uuid(),
 scheme_id uuid not null references public.degree_classification_schemes(id) on delete cascade,
 classification text not null,
 min_cgpa numeric(6,3) not null,
 max_cgpa numeric(6,3) not null,
 sequence_no integer not null default 1,
 description text,
 created_at timestamptz not null default now(),
 unique(scheme_id,classification),
 check(min_cgpa<=max_cgpa)
);
create table if not exists public.degree_classification_assignments(
 id uuid primary key default gen_random_uuid(),
 institution_id uuid not null references public.institutions(id) on delete cascade,
 programme_id uuid not null references public.programmes(id) on delete cascade,
 scheme_id uuid not null references public.degree_classification_schemes(id) on delete cascade,
 active boolean not null default true,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(institution_id,programme_id)
);

alter table public.graduation_reviews add column if not exists classification_scheme_id uuid references public.degree_classification_schemes(id) on delete set null;
alter table public.graduation_reviews add column if not exists award_classification text;

alter table public.degree_classification_schemes enable row level security;
alter table public.degree_classification_bands enable row level security;
alter table public.degree_classification_assignments enable row level security;
grant select,insert,update,delete on public.degree_classification_schemes,public.degree_classification_bands,public.degree_classification_assignments to authenticated;

create or replace function public.unimis_degree_classification_settings()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid;
begin
 v_inst:=public.unimis_progression_access(); if v_inst is null then raise exception 'Academic settings access required'; end if;
 return jsonb_build_object(
  'schemes',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'code',s.code,'gpa_scale',s.gpa_scale,'is_default',s.is_default,'active',s.active,'bands',coalesce((select jsonb_agg(jsonb_build_object('id',b.id,'classification',b.classification,'min_cgpa',b.min_cgpa,'max_cgpa',b.max_cgpa,'sequence_no',b.sequence_no,'description',b.description) order by b.sequence_no) from public.degree_classification_bands b where b.scheme_id=s.id),'[]'::jsonb)) order by s.is_default desc,s.name) from public.degree_classification_schemes s where s.institution_id=v_inst),'[]'::jsonb),
  'assignments',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'programme_id',a.programme_id,'programme_code',p.code,'programme_name',p.name,'scheme_id',a.scheme_id,'scheme_name',s.name) order by p.code) from public.degree_classification_assignments a join public.programmes p on p.id=a.programme_id join public.degree_classification_schemes s on s.id=a.scheme_id where a.institution_id=v_inst and a.active=true),'[]'::jsonb),
  'programmes',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'code',p.code,'name',p.name) order by p.code) from public.programmes p where p.institution_id=v_inst),'[]'::jsonb)
 );
end $$;

create or replace function public.unimis_save_degree_classification_scheme(p_scheme jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_inst uuid; v_id uuid; b jsonb;
begin
 v_inst:=public.unimis_progression_access(); if v_inst is null then raise exception 'Academic settings access required'; end if;
 if coalesce((p_scheme->>'name'),'')='' or coalesce((p_scheme->>'code'),'')='' then raise exception 'Scheme name and code are required'; end if;
 if coalesce((p_scheme->>'is_default')::boolean,false) then update public.degree_classification_schemes set is_default=false,updated_at=now() where institution_id=v_inst; end if;
 v_id:=nullif(p_scheme->>'id','')::uuid;
 if v_id is null then
  insert into public.degree_classification_schemes(institution_id,name,code,gpa_scale,is_default,active) values(v_inst,p_scheme->>'name',upper(p_scheme->>'code'),coalesce((p_scheme->>'gpa_scale')::numeric,4),coalesce((p_scheme->>'is_default')::boolean,false),true) returning id into v_id;
 else
  update public.degree_classification_schemes set name=p_scheme->>'name',code=upper(p_scheme->>'code'),gpa_scale=coalesce((p_scheme->>'gpa_scale')::numeric,4),is_default=coalesce((p_scheme->>'is_default')::boolean,false),updated_at=now() where id=v_id and institution_id=v_inst;
  if not found then raise exception 'Classification scheme not found'; end if;
  delete from public.degree_classification_bands where scheme_id=v_id;
 end if;
 for b in select value from jsonb_array_elements(coalesce(p_scheme->'bands','[]'::jsonb)) loop
  if (b->>'min_cgpa')::numeric>(b->>'max_cgpa')::numeric then raise exception 'Invalid CGPA range for %',b->>'classification'; end if;
  insert into public.degree_classification_bands(scheme_id,classification,min_cgpa,max_cgpa,sequence_no,description) values(v_id,b->>'classification',(b->>'min_cgpa')::numeric,(b->>'max_cgpa')::numeric,coalesce((b->>'sequence_no')::int,1),nullif(b->>'description',''));
 end loop;
 return v_id;
end $$;

create or replace function public.unimis_assign_degree_classification(p_programme_id uuid,p_scheme_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_inst uuid;
begin
 v_inst:=public.unimis_progression_access(); if v_inst is null then raise exception 'Academic settings access required'; end if;
 if not exists(select 1 from public.programmes where id=p_programme_id and institution_id=v_inst) then raise exception 'Programme not found'; end if;
 if not exists(select 1 from public.degree_classification_schemes where id=p_scheme_id and institution_id=v_inst and active=true) then raise exception 'Scheme not found'; end if;
 insert into public.degree_classification_assignments(institution_id,programme_id,scheme_id,active) values(v_inst,p_programme_id,p_scheme_id,true)
 on conflict(institution_id,programme_id) do update set scheme_id=excluded.scheme_id,active=true,updated_at=now();
end $$;

create or replace function public.unimis_resolve_degree_classification(p_programme_id uuid,p_cgpa numeric)
returns jsonb language plpgsql security definer set search_path='' stable as $$
declare v_inst uuid; v_scheme uuid; v_name text; v_class text;
begin
 v_inst:=public.unimis_progression_access(); if v_inst is null then raise exception 'Academic records access required'; end if;
 select a.scheme_id,s.name into v_scheme,v_name from public.degree_classification_assignments a join public.degree_classification_schemes s on s.id=a.scheme_id where a.institution_id=v_inst and a.programme_id=p_programme_id and a.active=true and s.active=true limit 1;
 if v_scheme is null then select id,name into v_scheme,v_name from public.degree_classification_schemes where institution_id=v_inst and is_default=true and active=true order by updated_at desc limit 1; end if;
 if v_scheme is not null and p_cgpa is not null then select classification into v_class from public.degree_classification_bands where scheme_id=v_scheme and p_cgpa>=min_cgpa and p_cgpa<=max_cgpa order by sequence_no limit 1; end if;
 return jsonb_build_object('scheme_id',v_scheme,'scheme_name',v_name,'classification',v_class);
end $$;

create or replace function public.unimis_load_standard_degree_classification()
returns uuid language plpgsql security definer set search_path='' as $$
declare v_inst uuid; v_id uuid;
begin
 v_inst:=public.unimis_progression_access(); if v_inst is null then raise exception 'Academic settings access required'; end if;
 select id into v_id from public.degree_classification_schemes where institution_id=v_inst and code='DEG-4.0';
 if v_id is null then
  if not exists(select 1 from public.degree_classification_schemes where institution_id=v_inst and is_default=true) then
   insert into public.degree_classification_schemes(institution_id,name,code,gpa_scale,is_default) values(v_inst,'Standard 4.0 Degree Classification','DEG-4.0',4,true) returning id into v_id;
  else insert into public.degree_classification_schemes(institution_id,name,code,gpa_scale,is_default) values(v_inst,'Standard 4.0 Degree Classification','DEG-4.0',4,false) returning id into v_id; end if;
  insert into public.degree_classification_bands(scheme_id,classification,min_cgpa,max_cgpa,sequence_no,description) values
   (v_id,'First Class',3.600,4.000,1,'Example institutional classification'),
   (v_id,'Second Class Upper',3.000,3.599,2,'Example institutional classification'),
   (v_id,'Second Class Lower',2.500,2.999,3,'Example institutional classification'),
   (v_id,'Third Class',2.000,2.499,4,'Example institutional classification');
 end if;
 return v_id;
end $$;

-- Graduation evaluation now resolves and stores the award classification snapshot.
create or replace function public.unimis_evaluate_graduation(p_academic_year_id uuid,p_programme_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid; rec record; v_final int; v_earned numeric; v_cgpa numeric; v_trails int; v_required numeric; v_reasons jsonb; v_decision text; v_class jsonb; n int:=0;
begin
 v_inst:=public.unimis_progression_access(); if v_inst is null then raise exception 'Graduation access required'; end if;
 perform public.unimis_sync_academic_trails(null);
 for rec in select s.id student_id,e.id enrolment_id,e.programme_id,e.current_level,p.duration_years,p.total_credits from public.students s join public.student_programme_enrolments e on e.student_id=s.id and e.is_primary=true join public.programmes p on p.id=e.programme_id where s.institution_id=v_inst and e.enrolment_status='active' and (p_programme_id is null or e.programme_id=p_programme_id)
 loop
  v_final:=greatest(100,round(coalesce(rec.duration_years,rec.current_level/100.0))::int*100); if rec.current_level<v_final then continue; end if;
  v_required:=rec.total_credits;
  select coalesce(sum(z.credit_hours),0),case when sum(z.credit_hours)>0 then round(sum(z.grade_point*z.credit_hours)/sum(z.credit_hours),3) end into v_earned,v_cgpa from (select distinct on(co.course_id) co.course_id,c.credit_hours,cr.grade_point from public.course_results cr join public.course_offerings co on co.id=cr.course_offering_id join public.courses c on c.id=co.course_id where cr.student_id=rec.student_id and cr.result_status='published' and cr.passed=true order by co.course_id,cr.published_at desc nulls last)z;
  select count(*) into v_trails from public.student_academic_trails where student_id=rec.student_id and status in('outstanding','registered');
  v_reasons:='[]'::jsonb;
  if v_required is null or v_required<=0 then v_reasons:=v_reasons||jsonb_build_array('Programme total credits are not configured'); elsif v_earned<v_required then v_reasons:=v_reasons||jsonb_build_array(format('Credits earned %s below programme requirement %s',v_earned,v_required)); end if;
  if v_trails>0 then v_reasons:=v_reasons||jsonb_build_array(format('%s outstanding trail course(s)',v_trails)); end if;
  v_class:=public.unimis_resolve_degree_classification(rec.programme_id,v_cgpa);
  if v_cgpa is not null and (v_class->>'scheme_id') is null then v_reasons:=v_reasons||jsonb_build_array('Degree classification scheme is not configured');
  elsif v_cgpa is not null and (v_class->>'classification') is null then v_reasons:=v_reasons||jsonb_build_array(format('CGPA %s does not match a degree classification band',v_cgpa)); end if;
  v_decision:=case when jsonb_array_length(v_reasons)=0 then 'eligible' else 'completion_exception' end;
  insert into public.graduation_reviews(institution_id,academic_year_id,student_id,programme_enrolment_id,programme_id,final_level,credits_required,credits_earned,cgpa,outstanding_trails,classification_scheme_id,award_classification,decision,reasons,evaluated_at,updated_at)
  values(v_inst,p_academic_year_id,rec.student_id,rec.enrolment_id,rec.programme_id,v_final,v_required,v_earned,v_cgpa,v_trails,nullif(v_class->>'scheme_id','')::uuid,v_class->>'classification',v_decision,v_reasons,now(),now())
  on conflict(academic_year_id,student_id,programme_enrolment_id) do update set final_level=excluded.final_level,credits_required=excluded.credits_required,credits_earned=excluded.credits_earned,cgpa=excluded.cgpa,outstanding_trails=excluded.outstanding_trails,classification_scheme_id=excluded.classification_scheme_id,award_classification=excluded.award_classification,decision=case when graduation_reviews.decision in('approved','graduated') then graduation_reviews.decision else excluded.decision end,reasons=excluded.reasons,evaluated_at=now(),updated_at=now(); n:=n+1;
 end loop;
 return jsonb_build_object('evaluated',n);
end $$;

create or replace function public.unimis_graduation_queue(p_academic_year_id uuid default null,p_programme_id uuid default null,p_decision text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid;
begin
 v_inst:=public.unimis_progression_access(); if v_inst is null then raise exception 'Graduation access required'; end if;
 return jsonb_build_object('summary',(select jsonb_build_object('total',count(*),'eligible',count(*) filter(where decision='eligible'),'exceptions',count(*) filter(where decision='completion_exception'),'approved',count(*) filter(where decision='approved'),'graduated',count(*) filter(where decision='graduated')) from public.graduation_reviews where institution_id=v_inst and (p_academic_year_id is null or academic_year_id=p_academic_year_id) and (p_programme_id is null or programme_id=p_programme_id)),
 'rows',coalesce((select jsonb_agg(to_jsonb(x) order by x.student_number) from (select g.id review_id,g.student_id,s.student_number,s.first_name,s.middle_name,s.last_name,p.code programme_code,p.name programme_name,p.award_type,g.final_level,g.credits_required,g.credits_earned,g.cgpa,g.award_classification,g.outstanding_trails,g.decision,g.reasons,g.evaluated_at,g.approved_at,g.graduation_date from public.graduation_reviews g join public.students s on s.id=g.student_id join public.programmes p on p.id=g.programme_id where g.institution_id=v_inst and (p_academic_year_id is null or g.academic_year_id=p_academic_year_id) and (p_programme_id is null or g.programme_id=p_programme_id) and (p_decision is null or p_decision='' or g.decision=p_decision))x),'[]'::jsonb));
end $$;

grant execute on function public.unimis_degree_classification_settings(),public.unimis_save_degree_classification_scheme(jsonb),public.unimis_assign_degree_classification(uuid,uuid),public.unimis_resolve_degree_classification(uuid,numeric),public.unimis_load_standard_degree_classification() to authenticated;

commit;
