-- UniMIS 051-053: Dual result entry + lecturer/exams analytics
begin;

create table if not exists public.course_result_entry_settings(
 id uuid primary key default gen_random_uuid(),
 institution_id uuid not null references public.institutions(id) on delete cascade,
 course_offering_id uuid not null references public.course_offerings(id) on delete cascade,
 entry_mode text not null default 'detailed' check(entry_mode in ('detailed','ca_exam')),
 ca_weight numeric(5,2) not null default 40 check(ca_weight>0 and ca_weight<100),
 exam_weight numeric(5,2) not null default 60 check(exam_weight>0 and exam_weight<100),
 configured_by uuid,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(course_offering_id),
 check(ca_weight+exam_weight=100)
);
alter table public.course_result_entry_settings enable row level security;
grant select on public.course_result_entry_settings to authenticated;

create or replace function public.unimis_configure_result_entry_mode(
 p_course_offering_id uuid,p_entry_mode text,p_ca_weight numeric default 40,p_exam_weight numeric default 60)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid;v_lp uuid;v_ca uuid;v_exam uuid;
begin
 select institution_id,lecturer_profile_id into v_inst,v_lp from public.unimis_current_lecturer();
 if not exists(select 1 from public.course_lecturers where institution_id=v_inst and lecturer_profile_id=v_lp and course_offering_id=p_course_offering_id)
 then raise exception 'You are not allocated to this course offering'; end if;
 if p_entry_mode not in ('detailed','ca_exam') then raise exception 'Invalid result entry mode'; end if;
 if p_ca_weight<=0 or p_exam_weight<=0 or p_ca_weight+p_exam_weight<>100 then raise exception 'CA and Exam weights must total 100%%'; end if;
 if exists(select 1 from public.course_results where institution_id=v_inst and course_offering_id=p_course_offering_id and result_status in ('submitted','approved','published'))
 then raise exception 'Result entry mode is locked after submission'; end if;

 insert into public.course_result_entry_settings(institution_id,course_offering_id,entry_mode,ca_weight,exam_weight,configured_by)
 values(v_inst,p_course_offering_id,p_entry_mode,p_ca_weight,p_exam_weight,auth.uid())
 on conflict(course_offering_id) do update set entry_mode=excluded.entry_mode,ca_weight=excluded.ca_weight,exam_weight=excluded.exam_weight,configured_by=auth.uid(),updated_at=now();

 if p_entry_mode='ca_exam' then
   -- Keep detailed items for audit, but cancel them so they cannot double-count.
   update public.assessment_items set status='cancelled',updated_at=now()
   where institution_id=v_inst and course_offering_id=p_course_offering_id
     and name not in ('Continuous Assessment','Final Examination')
     and status not in ('published');

   insert into public.assessment_items(institution_id,course_offering_id,name,assessment_type,max_score,weight_percent,sequence_no,status,created_by)
   values(v_inst,p_course_offering_id,'Continuous Assessment','other',p_ca_weight,p_ca_weight,1,'open',auth.uid())
   on conflict(course_offering_id,name) do update set max_score=excluded.max_score,weight_percent=excluded.weight_percent,status='open',updated_at=now()
   returning id into v_ca;

   insert into public.assessment_items(institution_id,course_offering_id,name,assessment_type,max_score,weight_percent,sequence_no,status,created_by)
   values(v_inst,p_course_offering_id,'Final Examination','final_exam',p_exam_weight,p_exam_weight,2,'open',auth.uid())
   on conflict(course_offering_id,name) do update set max_score=excluded.max_score,weight_percent=excluded.weight_percent,status='open',updated_at=now()
   returning id into v_exam;
 end if;
 return jsonb_build_object('mode',p_entry_mode,'ca_weight',p_ca_weight,'exam_weight',p_exam_weight);
end $$;
grant execute on function public.unimis_configure_result_entry_mode(uuid,text,numeric,numeric) to authenticated;

create or replace function public.unimis_ca_exam_marksheet(p_course_offering_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid;v_lp uuid;v_ca uuid;v_exam uuid;v_caw numeric;v_examw numeric;
begin
 select institution_id,lecturer_profile_id into v_inst,v_lp from public.unimis_current_lecturer();
 if not exists(select 1 from public.course_lecturers where institution_id=v_inst and lecturer_profile_id=v_lp and course_offering_id=p_course_offering_id)
 then raise exception 'You are not allocated to this course offering'; end if;
 select id,max_score into v_ca,v_caw from public.assessment_items where institution_id=v_inst and course_offering_id=p_course_offering_id and name='Continuous Assessment' and status<>'cancelled' limit 1;
 select id,max_score into v_exam,v_examw from public.assessment_items where institution_id=v_inst and course_offering_id=p_course_offering_id and name='Final Examination' and status<>'cancelled' limit 1;
 if v_ca is null or v_exam is null then raise exception 'Configure CA + Exam mode first'; end if;
 return jsonb_build_object('ca_item_id',v_ca,'exam_item_id',v_exam,'ca_max',v_caw,'exam_max',v_examw,'students',coalesce((
  select jsonb_agg(jsonb_build_object(
   'student_id',s.id,'course_registration_id',scr.id,'student_number',s.student_number,
   'student_name',concat_ws(' ',s.first_name,s.middle_name,s.last_name),
   'ca_score',ca.raw_score,'exam_score',ex.raw_score,
   'total_score',coalesce(ca.weighted_score,0)+coalesce(ex.weighted_score,0)
  ) order by s.last_name,s.first_name)
  from public.student_course_registrations scr
  join public.student_period_registrations spr on spr.id=scr.period_registration_id
  join public.students s on s.id=scr.student_id
  left join public.assessment_scores ca on ca.assessment_item_id=v_ca and ca.student_course_registration_id=scr.id
  left join public.assessment_scores ex on ex.assessment_item_id=v_exam and ex.student_course_registration_id=scr.id
  where scr.institution_id=v_inst and scr.course_offering_id=p_course_offering_id
    and lower(coalesce(scr.status,'')) not in ('dropped','cancelled','withdrawn')
    and lower(coalesce(spr.registration_status,''))='approved'
 ),'[]'::jsonb));
end $$;
grant execute on function public.unimis_ca_exam_marksheet(uuid) to authenticated;

create or replace function public.unimis_save_ca_exam_scores(p_course_offering_id uuid,p_records jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid;v_lp uuid;v_ca uuid;v_exam uuid;v_camax numeric;v_exammax numeric;r jsonb;v numeric;n int:=0;
begin
 select institution_id,lecturer_profile_id into v_inst,v_lp from public.unimis_current_lecturer();
 if not exists(select 1 from public.course_lecturers where institution_id=v_inst and lecturer_profile_id=v_lp and course_offering_id=p_course_offering_id)
 then raise exception 'You are not allocated to this course offering'; end if;
 if exists(select 1 from public.course_results where institution_id=v_inst and course_offering_id=p_course_offering_id and result_status in ('submitted','approved','published'))
 then raise exception 'Marks are locked because results have been submitted'; end if;
 select id,max_score into v_ca,v_camax from public.assessment_items where institution_id=v_inst and course_offering_id=p_course_offering_id and name='Continuous Assessment' and status<>'cancelled' limit 1;
 select id,max_score into v_exam,v_exammax from public.assessment_items where institution_id=v_inst and course_offering_id=p_course_offering_id and name='Final Examination' and status<>'cancelled' limit 1;
 if v_ca is null or v_exam is null then raise exception 'Configure CA + Exam mode first'; end if;

 for r in select * from jsonb_array_elements(coalesce(p_records,'[]'::jsonb)) loop
   if nullif(r->>'ca_score','') is not null then
    v=(r->>'ca_score')::numeric;if v<0 or v>v_camax then raise exception 'CA score outside 0-% for %',v_camax,r->>'student_number';end if;
    insert into public.assessment_scores(institution_id,assessment_item_id,student_course_registration_id,student_id,raw_score,weighted_score,status,entered_by,entered_at)
    values(v_inst,v_ca,(r->>'course_registration_id')::uuid,(r->>'student_id')::uuid,v,v,'entered',auth.uid(),now())
    on conflict(assessment_item_id,student_course_registration_id) do update set raw_score=excluded.raw_score,weighted_score=excluded.weighted_score,status='entered',entered_by=auth.uid(),entered_at=now(),updated_at=now();
   end if;
   if nullif(r->>'exam_score','') is not null then
    v=(r->>'exam_score')::numeric;if v<0 or v>v_exammax then raise exception 'Exam score outside 0-% for %',v_exammax,r->>'student_number';end if;
    insert into public.assessment_scores(institution_id,assessment_item_id,student_course_registration_id,student_id,raw_score,weighted_score,status,entered_by,entered_at)
    values(v_inst,v_exam,(r->>'course_registration_id')::uuid,(r->>'student_id')::uuid,v,v,'entered',auth.uid(),now())
    on conflict(assessment_item_id,student_course_registration_id) do update set raw_score=excluded.raw_score,weighted_score=excluded.weighted_score,status='entered',entered_by=auth.uid(),entered_at=now(),updated_at=now();
   end if;n:=n+1;
 end loop;
 return jsonb_build_object('saved',n);
end $$;
grant execute on function public.unimis_save_ca_exam_scores(uuid,jsonb) to authenticated;

create or replace function public.unimis_result_analytics_core(p_inst uuid,p_course_offering_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_course uuid;v_n int;v_avg numeric;v_min numeric;v_max numeric;v_pass int;v_ca numeric;v_exam numeric;
begin
 select course_id into v_course from public.course_offerings where id=p_course_offering_id and institution_id=p_inst;
 with x as (
  select cr.total_score,cr.passed from public.course_results cr where cr.institution_id=p_inst and cr.course_offering_id=p_course_offering_id
  union all
  select q.total_score,gb.is_pass
  from (
   select scr.id,coalesce(sum(sc.weighted_score),0)::numeric total_score
   from public.student_course_registrations scr join public.student_period_registrations spr on spr.id=scr.period_registration_id
   join public.assessment_items ai on ai.course_offering_id=scr.course_offering_id and ai.status<>'cancelled'
   left join public.assessment_scores sc on sc.assessment_item_id=ai.id and sc.student_course_registration_id=scr.id
   where scr.institution_id=p_inst and scr.course_offering_id=p_course_offering_id and lower(spr.registration_status)='approved'
     and not exists(select 1 from public.course_results cr where cr.student_course_registration_id=scr.id)
   group by scr.id
  ) q
  left join lateral(select b.is_pass from public.grading_schemes gs join public.grade_bands b on b.grading_scheme_id=gs.id
   where gs.institution_id=p_inst and gs.status='active' and q.total_score between b.min_score and b.max_score order by gs.is_default desc,b.min_score desc limit 1) gb on true
 ) select count(*),round(avg(total_score),2),min(total_score),max(total_score),count(*) filter(where passed) into v_n,v_avg,v_min,v_max,v_pass from x;

 select round(avg(sc.raw_score),2) into v_ca from public.assessment_scores sc join public.assessment_items ai on ai.id=sc.assessment_item_id where ai.course_offering_id=p_course_offering_id and ai.name='Continuous Assessment';
 select round(avg(sc.raw_score),2) into v_exam from public.assessment_scores sc join public.assessment_items ai on ai.id=sc.assessment_item_id where ai.course_offering_id=p_course_offering_id and ai.name='Final Examination';

 return jsonb_build_object('student_count',coalesce(v_n,0),'average',coalesce(v_avg,0),'lowest',coalesce(v_min,0),'highest',coalesce(v_max,0),
 'pass_count',coalesce(v_pass,0),'fail_count',greatest(coalesce(v_n,0)-coalesce(v_pass,0),0),
 'pass_rate',case when v_n>0 then round(v_pass*100.0/v_n,1) else 0 end,'ca_average',v_ca,'exam_average',v_exam,
 'grade_distribution',coalesce((select jsonb_agg(jsonb_build_object('grade',letter_grade,'count',n) order by maxgp desc) from
   (select coalesce(cr.letter_grade,'—') letter_grade,count(*) n,max(coalesce(cr.grade_point,0)) maxgp from public.course_results cr where cr.institution_id=p_inst and cr.course_offering_id=p_course_offering_id group by cr.letter_grade) g),'[]'::jsonb),
 'trend',coalesce((select jsonb_agg(jsonb_build_object('period',z.period_name,'average',z.avg_score,'pass_rate',z.pass_rate,'students',z.n) order by z.start_date) from
   (select ap.name period_name,ap.start_date,count(*) n,round(avg(cr.total_score),2) avg_score,round(count(*) filter(where cr.passed)*100.0/nullif(count(*),0),1) pass_rate
    from public.course_results cr join public.course_offerings co on co.id=cr.course_offering_id join public.academic_periods ap on ap.id=co.academic_period_id
    where cr.institution_id=p_inst and co.course_id=v_course and cr.result_status in ('submitted','approved','published')
    group by ap.id,ap.name,ap.start_date) z),'[]'::jsonb));
end $$;

create or replace function public.unimis_lecturer_result_analytics(p_course_offering_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid;v_lp uuid;
begin
 select institution_id,lecturer_profile_id into v_inst,v_lp from public.unimis_current_lecturer();
 if not exists(select 1 from public.course_lecturers where institution_id=v_inst and lecturer_profile_id=v_lp and course_offering_id=p_course_offering_id) then raise exception 'You are not allocated to this course';end if;
 return public.unimis_result_analytics_core(v_inst,p_course_offering_id);
end $$;
grant execute on function public.unimis_lecturer_result_analytics(uuid) to authenticated;

create or replace function public.unimis_admin_result_analytics(p_course_offering_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid;
begin
 select iu.institution_id into v_inst from public.institution_users iu join public.roles r on r.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active' and lower(coalesce(r.code,r.name)) in ('admin','administrator','owner','registrar','superadmin','super_admin','exams_officer','examinations_officer') limit 1;
 if v_inst is null then raise exception 'Examinations review access required';end if;
 return public.unimis_result_analytics_core(v_inst,p_course_offering_id);
end $$;
grant execute on function public.unimis_admin_result_analytics(uuid) to authenticated;

commit;