begin;

alter table public.academic_progression_rules
  add column if not exists max_failed_courses integer;

create or replace function public.unimis_progression_rule_settings()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid;
begin
 v_inst:=public.unimis_progression_access();
 if v_inst is null then raise exception 'Progression settings access required'; end if;
 return jsonb_build_object(
  'programmes',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'code',p.code,'name',p.name) order by p.code) from public.programmes p where p.institution_id=v_inst),'[]'::jsonb),
  'rules',coalesce((select jsonb_agg(jsonb_build_object(
    'id',r.id,'programme_id',r.programme_id,'programme_code',p.code,'programme_name',p.name,
    'from_level',r.from_level,'to_level',r.to_level,'min_credits_earned',r.min_credits_earned,
    'max_failed_credits',r.max_failed_credits,'max_failed_courses',r.max_failed_courses,
    'min_cgpa',r.min_cgpa,'allow_carry_over',r.allow_carry_over,'is_active',r.is_active,
    'scope',case when r.programme_id is null then 'institution' else 'programme' end
   ) order by (r.programme_id is not null),r.from_level,p.code) from public.academic_progression_rules r left join public.programmes p on p.id=r.programme_id where r.institution_id=v_inst and r.is_active),'[]'::jsonb)
 );
end $$;

create or replace function public.unimis_save_progression_rule(p_rule jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid; v_id uuid; v_programme uuid; v_from int; v_to int;
begin
 v_inst:=public.unimis_progression_access(); if v_inst is null then raise exception 'Progression settings access required'; end if;
 v_id:=nullif(p_rule->>'id','')::uuid;
 v_programme:=nullif(p_rule->>'programme_id','')::uuid;
 v_from:=(p_rule->>'from_level')::int; v_to:=(p_rule->>'to_level')::int;
 if v_from is null or v_to is null or v_to<=v_from then raise exception 'Next level must be greater than current level'; end if;
 if v_programme is not null and not exists(select 1 from public.programmes where id=v_programme and institution_id=v_inst) then raise exception 'Programme not found'; end if;
 -- One active rule per scope/from-level. Updating or replacing a rule is deterministic.
 update public.academic_progression_rules set is_active=false,updated_at=now()
 where institution_id=v_inst and is_active and from_level=v_from
   and coalesce(programme_id,'00000000-0000-0000-0000-000000000000'::uuid)=coalesce(v_programme,'00000000-0000-0000-0000-000000000000'::uuid)
   and (v_id is null or id<>v_id);
 if v_id is not null and exists(select 1 from public.academic_progression_rules where id=v_id and institution_id=v_inst) then
  update public.academic_progression_rules set programme_id=v_programme,from_level=v_from,to_level=v_to,
   min_credits_earned=coalesce((p_rule->>'min_credits_earned')::numeric,0),
   max_failed_credits=coalesce((p_rule->>'max_failed_credits')::numeric,0),
   max_failed_courses=nullif(p_rule->>'max_failed_courses','')::int,
   min_cgpa=nullif(p_rule->>'min_cgpa','')::numeric,
   allow_carry_over=coalesce((p_rule->>'allow_carry_over')::boolean,true),is_active=true,updated_at=now()
  where id=v_id returning id into v_id;
 else
  insert into public.academic_progression_rules(institution_id,programme_id,from_level,to_level,min_credits_earned,max_failed_credits,max_failed_courses,min_cgpa,allow_carry_over,is_active)
  values(v_inst,v_programme,v_from,v_to,coalesce((p_rule->>'min_credits_earned')::numeric,0),coalesce((p_rule->>'max_failed_credits')::numeric,0),nullif(p_rule->>'max_failed_courses','')::int,nullif(p_rule->>'min_cgpa','')::numeric,coalesce((p_rule->>'allow_carry_over')::boolean,true),true)
  returning id into v_id;
 end if;
 return jsonb_build_object('id',v_id,'ok',true);
end $$;

create or replace function public.unimis_delete_progression_rule(p_rule_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid;
begin
 v_inst:=public.unimis_progression_access(); if v_inst is null then raise exception 'Progression settings access required'; end if;
 update public.academic_progression_rules set is_active=false,updated_at=now() where id=p_rule_id and institution_id=v_inst;
 return jsonb_build_object('ok',true);
end $$;

-- Evaluator: programme override -> institution default, now also honours maximum failed-course count.
create or replace function public.unimis_progression_evaluate(p_academic_year_id uuid,p_programme_id uuid default null,p_level integer default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid; v_count int:=0; rec record; v_rule record; v_registered numeric; v_earned numeric; v_failed numeric; v_failed_count int; v_cgpa numeric; v_failed_courses jsonb; v_decision text; v_reasons jsonb;
begin
 v_inst:=public.unimis_progression_access(); if v_inst is null then raise exception 'Progression access required'; end if;
 for rec in select s.id student_id,s.student_number,s.first_name,s.last_name,e.id enrolment_id,e.programme_id,e.current_level
  from public.students s join public.student_programme_enrolments e on e.student_id=s.id and e.is_primary=true
  where s.institution_id=v_inst and e.enrolment_status='active' and (p_programme_id is null or e.programme_id=p_programme_id) and (p_level is null or e.current_level=p_level)
 loop
  v_rule:=null;
  select * into v_rule from public.academic_progression_rules r where r.institution_id=v_inst and r.is_active and r.from_level=rec.current_level and (r.programme_id=rec.programme_id or r.programme_id is null) order by (r.programme_id is not null) desc limit 1;
  if v_rule.id is null then
   v_reasons:=jsonb_build_array('No active progression rule configured for this programme/level'); v_decision:='manual_review'; v_registered:=0;v_earned:=0;v_failed:=0;v_failed_count:=0;v_cgpa:=null;v_failed_courses:='[]'::jsonb;
  else
   select coalesce(sum(c.credit_hours),0),coalesce(sum(c.credit_hours) filter(where cr.passed=true and cr.result_status='published'),0),coalesce(sum(c.credit_hours) filter(where coalesce(cr.passed,false)=false and cr.result_status='published'),0),count(*) filter(where coalesce(cr.passed,false)=false and cr.result_status='published'),case when sum(c.credit_hours) filter(where cr.result_status='published')>0 then round(sum(coalesce(cr.grade_point,0)*c.credit_hours) filter(where cr.result_status='published')/sum(c.credit_hours) filter(where cr.result_status='published'),3) end,coalesce(jsonb_agg(jsonb_build_object('course_code',c.code,'course_name',c.name,'credits',c.credit_hours,'score',cr.total_score,'grade',cr.letter_grade)) filter(where coalesce(cr.passed,false)=false and cr.result_status='published'),'[]'::jsonb)
   into v_registered,v_earned,v_failed,v_failed_count,v_cgpa,v_failed_courses
   from public.student_course_registrations scr join public.course_offerings co on co.id=scr.course_offering_id join public.academic_periods ap on ap.id=co.academic_period_id join public.courses c on c.id=co.course_id left join public.course_results cr on cr.student_course_registration_id=scr.id
   where scr.student_id=rec.student_id and ap.academic_year_id=p_academic_year_id and scr.status<>'dropped';
   v_reasons:='[]'::jsonb;
   if v_registered=0 then v_reasons:=v_reasons||jsonb_build_array('No registered courses found for the academic year'); end if;
   if v_earned<v_rule.min_credits_earned then v_reasons:=v_reasons||jsonb_build_array(format('Credits earned %s below required %s',v_earned,v_rule.min_credits_earned)); end if;
   if v_failed>v_rule.max_failed_credits then v_reasons:=v_reasons||jsonb_build_array(format('Failed credits %s exceed allowed %s',v_failed,v_rule.max_failed_credits)); end if;
   if v_rule.max_failed_courses is not null and v_failed_count>v_rule.max_failed_courses then v_reasons:=v_reasons||jsonb_build_array(format('Failed courses %s exceed allowed %s',v_failed_count,v_rule.max_failed_courses)); end if;
   if v_rule.min_cgpa is not null and coalesce(v_cgpa,0)<v_rule.min_cgpa then v_reasons:=v_reasons||jsonb_build_array(format('CGPA %s below required %s',coalesce(v_cgpa,0),v_rule.min_cgpa)); end if;
   if v_registered=0 then v_decision:='manual_review'; elsif jsonb_array_length(v_reasons)=0 and v_failed>0 and v_rule.allow_carry_over then v_decision:='carry_over'; elsif jsonb_array_length(v_reasons)=0 then v_decision:='eligible'; else v_decision:='manual_review'; end if;
  end if;
  insert into public.student_progression_reviews(institution_id,academic_year_id,student_id,programme_enrolment_id,programme_id,from_level,proposed_level,decision,credits_registered,credits_earned,failed_credits,courses_failed,cgpa,reasons,failed_courses,evaluated_at,updated_at)
  values(v_inst,p_academic_year_id,rec.student_id,rec.enrolment_id,rec.programme_id,rec.current_level,coalesce(v_rule.to_level,rec.current_level),v_decision,v_registered,v_earned,v_failed,v_failed_count,v_cgpa,v_reasons,v_failed_courses,now(),now())
  on conflict(academic_year_id,student_id,programme_enrolment_id) do update set proposed_level=excluded.proposed_level,decision=excluded.decision,credits_registered=excluded.credits_registered,credits_earned=excluded.credits_earned,failed_credits=excluded.failed_credits,courses_failed=excluded.courses_failed,cgpa=excluded.cgpa,reasons=excluded.reasons,failed_courses=excluded.failed_courses,evaluated_at=now(),updated_at=now();
  v_count:=v_count+1;
 end loop;
 return jsonb_build_object('evaluated',v_count);
end $$;

grant execute on function public.unimis_progression_rule_settings() to authenticated;
grant execute on function public.unimis_save_progression_rule(jsonb) to authenticated;
grant execute on function public.unimis_delete_progression_rule(uuid) to authenticated;
commit;
