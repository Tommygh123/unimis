
begin;
create or replace function public.unimis_lecturer_assessments(p_course_offering_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid; v_lp uuid;
begin
 select institution_id,lecturer_profile_id into v_inst,v_lp from public.unimis_current_lecturer();
 if not exists(select 1 from public.course_lecturers where institution_id=v_inst and lecturer_profile_id=v_lp and course_offering_id=p_course_offering_id) then raise exception 'You are not allocated to this course offering'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'name',a.name,'assessment_type',a.assessment_type,'max_score',a.max_score,'weight_percent',a.weight_percent,'due_date',a.due_date,'sequence_no',a.sequence_no,'status',a.status) order by a.sequence_no,a.created_at) from public.assessment_items a where a.institution_id=v_inst and a.course_offering_id=p_course_offering_id),'[]'::jsonb);
end $$;
grant execute on function public.unimis_lecturer_assessments(uuid) to authenticated;

create or replace function public.unimis_create_assessment(p_course_offering_id uuid,p_name text,p_assessment_type text,p_max_score numeric,p_weight_percent numeric,p_due_date date default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_inst uuid; v_lp uuid; v_id uuid; v_total numeric; v_seq int;
begin
 select institution_id,lecturer_profile_id into v_inst,v_lp from public.unimis_current_lecturer();
 if not exists(select 1 from public.course_lecturers where institution_id=v_inst and lecturer_profile_id=v_lp and course_offering_id=p_course_offering_id) then raise exception 'You are not allocated to this course offering'; end if;
 if p_assessment_type not in ('quiz','assignment','midsem','project','practical','presentation','final_exam','other') then raise exception 'Invalid assessment type'; end if;
 select coalesce(sum(weight_percent),0) into v_total from public.assessment_items where course_offering_id=p_course_offering_id and status<>'cancelled';
 if v_total+p_weight_percent>100 then raise exception 'Assessment weights cannot exceed 100 percent. Current total: %',v_total; end if;
 select coalesce(max(sequence_no),0)+1 into v_seq from public.assessment_items where course_offering_id=p_course_offering_id;
 insert into public.assessment_items(institution_id,course_offering_id,name,assessment_type,max_score,weight_percent,due_date,sequence_no,status,created_by)
 values(v_inst,p_course_offering_id,btrim(p_name),p_assessment_type,p_max_score,p_weight_percent,p_due_date,v_seq,'draft',auth.uid()) returning id into v_id;
 return v_id;
end $$;
grant execute on function public.unimis_create_assessment(uuid,text,text,numeric,numeric,date) to authenticated;

create or replace function public.unimis_assessment_marksheet(p_assessment_item_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid; v_lp uuid; v_off uuid; v_max numeric; v_weight numeric;
begin
 select institution_id,lecturer_profile_id into v_inst,v_lp from public.unimis_current_lecturer();
 select course_offering_id,max_score,weight_percent into v_off,v_max,v_weight from public.assessment_items where id=p_assessment_item_id and institution_id=v_inst;
 if v_off is null or not exists(select 1 from public.course_lecturers where institution_id=v_inst and lecturer_profile_id=v_lp and course_offering_id=v_off) then raise exception 'Assessment is not in one of your allocated courses'; end if;
 return jsonb_build_object('max_score',v_max,'weight_percent',v_weight,'students',coalesce((select jsonb_agg(jsonb_build_object('student_id',s.id,'course_registration_id',scr.id,'student_number',s.student_number,'first_name',s.first_name,'middle_name',s.middle_name,'last_name',s.last_name,'score_id',sc.id,'raw_score',sc.raw_score,'weighted_score',sc.weighted_score,'score_status',sc.status,'remarks',sc.remarks) order by s.last_name,s.first_name) from public.student_course_registrations scr join public.student_period_registrations spr on spr.id=scr.period_registration_id join public.students s on s.id=scr.student_id left join public.assessment_scores sc on sc.assessment_item_id=p_assessment_item_id and sc.student_course_registration_id=scr.id where scr.institution_id=v_inst and scr.course_offering_id=v_off and lower(coalesce(scr.status,'')) not in ('dropped','cancelled','withdrawn') and lower(coalesce(spr.registration_status,''))='approved'),'[]'::jsonb));
end $$;
grant execute on function public.unimis_assessment_marksheet(uuid) to authenticated;

create or replace function public.unimis_save_assessment_scores(p_assessment_item_id uuid,p_records jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid; v_lp uuid; v_off uuid; v_max numeric; v_weight numeric; r jsonb; v_raw numeric; n int:=0;
begin
 select institution_id,lecturer_profile_id into v_inst,v_lp from public.unimis_current_lecturer();
 select course_offering_id,max_score,weight_percent into v_off,v_max,v_weight from public.assessment_items where id=p_assessment_item_id and institution_id=v_inst;
 if v_off is null or not exists(select 1 from public.course_lecturers where institution_id=v_inst and lecturer_profile_id=v_lp and course_offering_id=v_off) then raise exception 'Assessment is not in one of your allocated courses'; end if;
 for r in select * from jsonb_array_elements(coalesce(p_records,'[]'::jsonb)) loop
   if nullif(r->>'raw_score','') is null then continue; end if;
   v_raw:=(r->>'raw_score')::numeric;
   if v_raw<0 or v_raw>v_max then raise exception 'Score % is outside allowed maximum % for student %',v_raw,v_max,r->>'student_number'; end if;
   if not exists(select 1 from public.student_course_registrations scr join public.student_period_registrations spr on spr.id=scr.period_registration_id where scr.id=(r->>'course_registration_id')::uuid and scr.student_id=(r->>'student_id')::uuid and scr.course_offering_id=v_off and lower(coalesce(scr.status,'')) not in ('dropped','cancelled','withdrawn') and lower(coalesce(spr.registration_status,''))='approved') then raise exception 'Student % is not on the approved class list',r->>'student_number'; end if;
   insert into public.assessment_scores(institution_id,assessment_item_id,student_course_registration_id,student_id,raw_score,weighted_score,status,entered_by,entered_at,remarks)
   values(v_inst,p_assessment_item_id,(r->>'course_registration_id')::uuid,(r->>'student_id')::uuid,v_raw,round((v_raw/v_max)*v_weight,2),'entered',auth.uid(),now(),nullif(btrim(r->>'remarks'),''))
   on conflict(assessment_item_id,student_course_registration_id) do update set raw_score=excluded.raw_score,weighted_score=excluded.weighted_score,status='entered',entered_by=auth.uid(),entered_at=now(),remarks=excluded.remarks,updated_at=now();
   n:=n+1;
 end loop;
 return jsonb_build_object('saved',n);
end $$;
grant execute on function public.unimis_save_assessment_scores(uuid,jsonb) to authenticated;
commit;
