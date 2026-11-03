
-- UniMIS 047 — Course result submission, approval and publication
begin;

create or replace function public.unimis_lecturer_result_preview(p_course_offering_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid; v_lp uuid; v_scheme uuid; v_weight numeric; v_count int;
begin
 select institution_id,lecturer_profile_id into v_inst,v_lp from public.unimis_current_lecturer();
 if not exists(select 1 from public.course_lecturers where institution_id=v_inst and lecturer_profile_id=v_lp and course_offering_id=p_course_offering_id)
 then raise exception 'You are not allocated to this course offering'; end if;

 select id into v_scheme from public.grading_schemes
 where institution_id=v_inst and status='active'
 order by is_default desc,created_at limit 1;
 if v_scheme is null then raise exception 'No active grading scheme is configured for this institution'; end if;

 select coalesce(sum(weight_percent),0),count(*) into v_weight,v_count
 from public.assessment_items where institution_id=v_inst and course_offering_id=p_course_offering_id and status<>'cancelled';

 return jsonb_build_object(
  'grading_scheme_id',v_scheme,'assessment_weight',v_weight,'assessment_count',v_count,
  'ready',v_count>0 and v_weight=100,
  'students',coalesce((
   select jsonb_agg(jsonb_build_object(
    'student_id',q.student_id,'course_registration_id',q.scr_id,'student_number',q.student_number,
    'student_name',q.student_name,'total_score',q.total_score,'missing_assessments',q.missing_count,
    'letter_grade',gb.letter_grade,'grade_point',gb.grade_point,'passed',gb.is_pass,
    'result_status',cr.result_status,'remarks',cr.remarks
   ) order by q.student_name)
   from (
    select s.id student_id,scr.id scr_id,s.student_number,
      concat_ws(' ',s.first_name,s.middle_name,s.last_name) student_name,
      coalesce(sum(sc.weighted_score),0)::numeric(7,2) total_score,
      count(ai.id) filter(where sc.id is null) missing_count
    from public.student_course_registrations scr
    join public.student_period_registrations spr on spr.id=scr.period_registration_id
    join public.students s on s.id=scr.student_id
    cross join public.assessment_items ai
    left join public.assessment_scores sc on sc.assessment_item_id=ai.id and sc.student_course_registration_id=scr.id
    where scr.institution_id=v_inst and scr.course_offering_id=p_course_offering_id
      and lower(coalesce(scr.status,'')) not in ('dropped','cancelled','withdrawn')
      and lower(coalesce(spr.registration_status,''))='approved'
      and ai.institution_id=v_inst and ai.course_offering_id=p_course_offering_id and ai.status<>'cancelled'
    group by s.id,scr.id,s.student_number,s.first_name,s.middle_name,s.last_name
   ) q
   left join lateral (
     select b.* from public.grade_bands b
     where b.institution_id=v_inst and b.grading_scheme_id=v_scheme
       and q.total_score>=b.min_score and q.total_score<=b.max_score
     order by b.min_score desc limit 1
   ) gb on true
   left join public.course_results cr on cr.student_course_registration_id=q.scr_id
  ),'[]'::jsonb));
end $$;
grant execute on function public.unimis_lecturer_result_preview(uuid) to authenticated;

create or replace function public.unimis_submit_course_results(p_course_offering_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid; v_lp uuid; v_scheme uuid; v_weight numeric; v_assess int; r record; b record; n int:=0; old_status text;
begin
 select institution_id,lecturer_profile_id into v_inst,v_lp from public.unimis_current_lecturer();
 if not exists(select 1 from public.course_lecturers where institution_id=v_inst and lecturer_profile_id=v_lp and course_offering_id=p_course_offering_id)
 then raise exception 'You are not allocated to this course offering'; end if;
 select id into v_scheme from public.grading_schemes where institution_id=v_inst and status='active' order by is_default desc,created_at limit 1;
 if v_scheme is null then raise exception 'No active grading scheme is configured'; end if;
 select coalesce(sum(weight_percent),0),count(*) into v_weight,v_assess from public.assessment_items where institution_id=v_inst and course_offering_id=p_course_offering_id and status<>'cancelled';
 if v_assess=0 or v_weight<>100 then raise exception 'Assessment weights must total exactly 100%% before results can be submitted. Current total: %%%',v_weight; end if;

 for r in
  select s.id student_id,scr.id scr_id,coalesce(sum(sc.weighted_score),0)::numeric(7,2) total_score,
    count(ai.id) filter(where sc.id is null) missing_count
  from public.student_course_registrations scr
  join public.student_period_registrations spr on spr.id=scr.period_registration_id
  join public.students s on s.id=scr.student_id
  cross join public.assessment_items ai
  left join public.assessment_scores sc on sc.assessment_item_id=ai.id and sc.student_course_registration_id=scr.id
  where scr.institution_id=v_inst and scr.course_offering_id=p_course_offering_id
    and lower(coalesce(scr.status,'')) not in ('dropped','cancelled','withdrawn')
    and lower(coalesce(spr.registration_status,''))='approved'
    and ai.institution_id=v_inst and ai.course_offering_id=p_course_offering_id and ai.status<>'cancelled'
  group by s.id,scr.id
 loop
   if r.missing_count>0 then raise exception 'Cannot submit: at least one registered student has missing assessment marks'; end if;
   select * into b from public.grade_bands where institution_id=v_inst and grading_scheme_id=v_scheme and r.total_score>=min_score and r.total_score<=max_score order by min_score desc limit 1;
   if b.id is null then raise exception 'No grade band covers score %',r.total_score; end if;
   select result_status into old_status from public.course_results where student_course_registration_id=r.scr_id;
   if old_status in ('approved','published') then raise exception 'Approved or published results cannot be resubmitted'; end if;
   insert into public.course_results(institution_id,student_course_registration_id,student_id,course_offering_id,grading_scheme_id,total_score,letter_grade,grade_point,result_status,passed,submitted_by,submitted_at)
   values(v_inst,r.scr_id,r.student_id,p_course_offering_id,v_scheme,r.total_score,b.letter_grade,b.grade_point,'submitted',b.is_pass,auth.uid(),now())
   on conflict(student_course_registration_id) do update set grading_scheme_id=excluded.grading_scheme_id,total_score=excluded.total_score,letter_grade=excluded.letter_grade,grade_point=excluded.grade_point,result_status='submitted',passed=excluded.passed,submitted_by=auth.uid(),submitted_at=now(),approved_by=null,approved_at=null,published_at=null,updated_at=now();
   insert into public.result_approval_history(institution_id,course_result_id,old_status,new_status,action_by,action_at,notes)
   select v_inst,id,coalesce(old_status,'draft'),'submitted',auth.uid(),now(),'Submitted by lecturer' from public.course_results where student_course_registration_id=r.scr_id;
   n:=n+1;
 end loop;
 return jsonb_build_object('submitted',n);
end $$;
grant execute on function public.unimis_submit_course_results(uuid) to authenticated;

-- Lock marks once the corresponding course result has entered approval.
create or replace function public.unimis_save_assessment_scores(p_assessment_item_id uuid,p_records jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid; v_lp uuid; v_off uuid; v_max numeric; v_weight numeric; r jsonb; v_raw numeric; n int:=0;
begin
 select institution_id,lecturer_profile_id into v_inst,v_lp from public.unimis_current_lecturer();
 select course_offering_id,max_score,weight_percent into v_off,v_max,v_weight from public.assessment_items where id=p_assessment_item_id and institution_id=v_inst;
 if v_off is null or not exists(select 1 from public.course_lecturers where institution_id=v_inst and lecturer_profile_id=v_lp and course_offering_id=v_off) then raise exception 'Assessment is not in one of your allocated courses'; end if;
 if exists(select 1 from public.course_results where institution_id=v_inst and course_offering_id=v_off and result_status in ('submitted','approved','published'))
 then raise exception 'Marks are locked because course results have been submitted for approval'; end if;
 for r in select * from jsonb_array_elements(coalesce(p_records,'[]'::jsonb)) loop
   if nullif(r->>'raw_score','') is null then continue; end if;
   v_raw:=(r->>'raw_score')::numeric;
   if v_raw<0 or v_raw>v_max then raise exception 'Score % is outside allowed maximum % for student %',v_raw,v_max,r->>'student_number'; end if;
   insert into public.assessment_scores(institution_id,assessment_item_id,student_course_registration_id,student_id,raw_score,weighted_score,status,entered_by,entered_at,remarks)
   values(v_inst,p_assessment_item_id,(r->>'course_registration_id')::uuid,(r->>'student_id')::uuid,v_raw,round((v_raw/v_max)*v_weight,2),'entered',auth.uid(),now(),nullif(btrim(r->>'remarks'),''))
   on conflict(assessment_item_id,student_course_registration_id) do update set raw_score=excluded.raw_score,weighted_score=excluded.weighted_score,status='entered',entered_by=auth.uid(),entered_at=now(),remarks=excluded.remarks,updated_at=now();
   n:=n+1;
 end loop;
 return jsonb_build_object('saved',n);
end $$;

create or replace function public.unimis_results_admin_queue()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid;
begin
 select iu.institution_id into v_inst
 from public.institution_users iu join public.roles r on r.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active' and r.code in ('admin','owner') limit 1;
 if v_inst is null then raise exception 'Administrator access required'; end if;
 return coalesce((
  select jsonb_agg(x order by x->>'course_code')
  from (
   select jsonb_build_object(
    'course_offering_id',cr.course_offering_id,'course_code',c.code,'course_name',c.name,
    'academic_period_id',co.academic_period_id,'result_status',min(cr.result_status),
    'student_count',count(*),'submitted_at',max(cr.submitted_at),'approved_at',max(cr.approved_at),'published_at',max(cr.published_at)
   ) x
   from public.course_results cr join public.course_offerings co on co.id=cr.course_offering_id join public.courses c on c.id=co.course_id
   where cr.institution_id=v_inst
   group by cr.course_offering_id,c.code,c.name,co.academic_period_id
  ) q
 ),'[]'::jsonb);
end $$;
grant execute on function public.unimis_results_admin_queue() to authenticated;

create or replace function public.unimis_admin_course_results(p_course_offering_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid;
begin
 select iu.institution_id into v_inst from public.institution_users iu join public.roles r on r.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active' and r.code in ('admin','owner') limit 1;
 if v_inst is null then raise exception 'Administrator access required'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',cr.id,'student_number',s.student_number,'student_name',concat_ws(' ',s.first_name,s.middle_name,s.last_name),'total_score',cr.total_score,'letter_grade',cr.letter_grade,'grade_point',cr.grade_point,'passed',cr.passed,'result_status',cr.result_status,'remarks',cr.remarks) order by s.last_name,s.first_name)
 from public.course_results cr join public.students s on s.id=cr.student_id where cr.institution_id=v_inst and cr.course_offering_id=p_course_offering_id),'[]'::jsonb);
end $$;
grant execute on function public.unimis_admin_course_results(uuid) to authenticated;

create or replace function public.unimis_admin_result_action(p_course_offering_id uuid,p_action text,p_notes text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid; v_old text; v_new text; n int:=0; r record;
begin
 select iu.institution_id into v_inst from public.institution_users iu join public.roles ro on ro.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active' and ro.code in ('admin','owner') limit 1;
 if v_inst is null then raise exception 'Administrator access required'; end if;
 if p_action='approve' then v_old:='submitted';v_new:='approved';
 elsif p_action='publish' then v_old:='approved';v_new:='published';
 elsif p_action='return' then v_old:='submitted';v_new:='draft';
 else raise exception 'Invalid result action'; end if;
 for r in select id from public.course_results where institution_id=v_inst and course_offering_id=p_course_offering_id and result_status=v_old loop
   update public.course_results set result_status=v_new,
     approved_by=case when v_new='approved' then auth.uid() when v_new='draft' then null else approved_by end,
     approved_at=case when v_new='approved' then now() when v_new='draft' then null else approved_at end,
     published_at=case when v_new='published' then now() when v_new='draft' then null else published_at end,
     remarks=case when nullif(btrim(coalesce(p_notes,'')),'') is not null then p_notes else remarks end,updated_at=now()
   where id=r.id;
   insert into public.result_approval_history(institution_id,course_result_id,old_status,new_status,action_by,action_at,notes)
   values(v_inst,r.id,v_old,v_new,auth.uid(),now(),nullif(btrim(coalesce(p_notes,'')),''));
   n:=n+1;
 end loop;
 if n=0 then raise exception 'No % results found for this course',v_old; end if;
 return jsonb_build_object('updated',n,'status',v_new);
end $$;
grant execute on function public.unimis_admin_result_action(uuid,text,text) to authenticated;

create or replace function public.unimis_student_published_results()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_student uuid;
begin
 select id into v_student from public.students where user_id=auth.uid() and status='active' limit 1;
 if v_student is null then raise exception 'Student account not found'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('course_code',course_code,'course_name',course_name,'academic_year',academic_year,'academic_period',academic_period,'credit_hours',credit_hours,'total_score',total_score,'letter_grade',letter_grade,'grade_point',grade_point,'quality_points',quality_points,'passed',passed) order by academic_year,academic_period,course_code)
 from public.v_student_results where student_id=v_student and result_status='published'),'[]'::jsonb);
end $$;
grant execute on function public.unimis_student_published_results() to authenticated;
commit;
