-- Preserve review history; projected review is independently available to academic coordinators.
update public.unimis_review_config130 set review_mode='panel',stages=array['department','central','final'],enabled=false,updated_at=now() where review_mode='projected';
create or replace function public.unimis_create_projected_batch132(p_inst uuid,p_department uuid,p_period uuid,p_title text,p_results uuid[])
returns uuid language plpgsql security definer set search_path='' as $$
declare cfg public.unimis_review_config130; c public.unimis_committees130; fid uuid; rid uuid;i int; n int;
begin
 if not public.unimis_review_manager130(p_inst) then raise exception 'Academic review coordination required';end if;
 perform 1 from public.institutions where id=p_inst for update;
 select * into cfg from public.unimis_review_config130 where institution_id=p_inst and enabled;

 select faculty_id into fid from public.departments where id=p_department and institution_id=p_inst;
 if fid is null or not exists(select 1 from public.academic_periods where id=p_period and institution_id=p_inst) then raise exception 'Choose a school department and semester';end if;

 if length(trim(coalesce(p_title,'')))<3 or coalesce(cardinality(p_results),0)=0 then raise exception 'Title and selected submitted results required';end if;
 perform cr.id from public.course_results cr join public.student_course_registrations scr on scr.id=cr.student_course_registration_id and scr.institution_id=p_inst
 join public.student_period_registrations spr on spr.id=scr.period_registration_id and spr.institution_id=p_inst
 join public.student_programme_enrolments en on en.id=spr.programme_enrolment_id and en.institution_id=p_inst join public.programmes p on p.id=en.programme_id and p.institution_id=p_inst
 where cr.institution_id=p_inst and spr.academic_period_id=p_period and p.department_id=p_department and scr.status not in ('dropped','withdrawn') and cr.id=any(p_results) and cr.result_status='submitted' and cr.submitted_by is not null and cr.total_score is not null and cr.grade_point is not null and cr.letter_grade is not null and cr.passed is not null and cr.student_id=scr.student_id and spr.student_id=scr.student_id and en.student_id=spr.student_id for update of cr;
 if exists(select 1 from public.unimis_batch_results130 br join public.unimis_result_batches130 b on b.id=br.batch_id join public.course_results cr on cr.id=br.result_id
 join public.student_course_registrations scr on scr.id=cr.student_course_registration_id join public.student_period_registrations spr on spr.id=scr.period_registration_id
 join public.student_programme_enrolments en on en.id=spr.programme_enrolment_id join public.programmes p on p.id=en.programme_id
 where cr.institution_id=p_inst and spr.academic_period_id=p_period and p.department_id=p_department and cr.id=any(p_results) and b.status in ('review','ready','publishing')) then raise exception 'These results already belong to an open review batch';end if;
 insert into public.unimis_result_batches130(institution_id,department_id,academic_period_id,title,stages,committees,created_by)
 values(p_inst,p_department,p_period,trim(p_title),array['projected'],array[]::uuid[],auth.uid()) returning id into rid;
 insert into public.unimis_batch_results130(batch_id,result_id,snapshot)
 select rid,cr.id,jsonb_build_object('student_number',s.student_number,'student_name',concat_ws(' ',s.first_name,s.middle_name,s.last_name),'course_code',co.code,'course_name',co.name,'credits',co.credit_hours,'programme',p.code,'level',spr.level_number,
 'score',cr.total_score,'grade',cr.letter_grade,'grade_point',cr.grade_point,'quality_points',cr.quality_points,'passed',cr.passed,'submitted_by',cr.submitted_by,'initial_status',cr.result_status)
 from public.course_results cr join public.students s on s.id=cr.student_id and s.institution_id=p_inst
 join public.course_offerings off on off.id=cr.course_offering_id and off.institution_id=p_inst join public.courses co on co.id=off.course_id and co.institution_id=p_inst
 join public.student_course_registrations scr on scr.id=cr.student_course_registration_id and scr.institution_id=p_inst
 join public.student_period_registrations spr on spr.id=scr.period_registration_id and spr.institution_id=p_inst
 join public.student_programme_enrolments en on en.id=spr.programme_enrolment_id and en.institution_id=p_inst join public.programmes p on p.id=en.programme_id and p.institution_id=p_inst
 where cr.institution_id=p_inst and spr.academic_period_id=p_period and p.department_id=p_department and scr.status not in ('dropped','withdrawn') and cr.id=any(p_results) and cr.result_status='submitted' and cr.submitted_by is not null and cr.total_score is not null and cr.grade_point is not null and cr.letter_grade is not null and cr.passed is not null and cr.student_id=scr.student_id and spr.student_id=scr.student_id and en.student_id=spr.student_id;
 get diagnostics n=row_count;if n<>(select count(distinct x) from unnest(p_results) x) then raise exception 'Every selected result must be submitted and belong to this department and semester';end if;if n=0 then raise exception 'No submitted results for this department and semester; historical published results are not re-reviewed';end if;
 insert into public.unimis_review_events130(batch_id,actor,action,note) values(rid,auth.uid(),'create_batch','Frozen snapshot: '||n||' results');return rid;
end $$;
create or replace function public.unimis_projected_candidates133(p_inst uuid,p_period uuid,p_status text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.unimis_review_manager130(p_inst) then raise exception 'Academic review coordination required';end if;
 return coalesce((select jsonb_agg(x.item) from ( select jsonb_build_object('result_id',cr.id,'department_id',d.id,'department',d.name,'faculty_id',f.id,'faculty',f.name)||jsonb_build_object('student_number',s.student_number,'student_name',concat_ws(' ',s.first_name,s.middle_name,s.last_name),'course_code',co.code,'course_name',co.name,'credits',co.credit_hours,'programme',p.code,'level',spr.level_number,
 'score',cr.total_score,'grade',cr.letter_grade,'grade_point',cr.grade_point,'quality_points',cr.quality_points,'passed',cr.passed,'submitted_by',cr.submitted_by,'initial_status',cr.result_status) item
 from public.course_results cr join public.students s on s.id=cr.student_id and s.institution_id=p_inst
 join public.course_offerings off on off.id=cr.course_offering_id and off.institution_id=p_inst join public.courses co on co.id=off.course_id and co.institution_id=p_inst
 join public.student_course_registrations scr on scr.id=cr.student_course_registration_id and scr.institution_id=p_inst
 join public.student_period_registrations spr on spr.id=scr.period_registration_id and spr.institution_id=p_inst
 join public.student_programme_enrolments en on en.id=spr.programme_enrolment_id and en.institution_id=p_inst join public.programmes p on p.id=en.programme_id and p.institution_id=p_inst
 join public.departments d on d.id=p.department_id and d.institution_id=p_inst join public.faculties f on f.id=d.faculty_id and f.institution_id=p_inst
 where cr.institution_id=p_inst and spr.academic_period_id=p_period and scr.status not in ('dropped','withdrawn') and cr.result_status=p_status and p_status in ('submitted','approved') and cr.submitted_by is not null and cr.total_score is not null and cr.grade_point is not null and cr.letter_grade is not null and cr.passed is not null and cr.student_id=scr.student_id and spr.student_id=scr.student_id and en.student_id=spr.student_id and (p_status='submitted' or exists(select 1 from public.unimis_batch_results130 bx join public.unimis_result_batches130 bb on bb.id=bx.batch_id where bx.result_id=cr.id and bb.stages=array['projected'] and bb.status='ready')) and not exists(select 1 from public.unimis_batch_results130 br join public.unimis_result_batches130 b on b.id=br.batch_id where br.result_id=cr.id and b.status in ('review','ready','publishing') and not (p_status='approved' and b.stages=array['projected'] and b.status='ready'))) x),'[]'::jsonb);
end $$;
create or replace function public.unimis_save_review_config130(p_inst uuid,p_mode text)
returns void language plpgsql security definer set search_path='' as $$
declare stages text[];
begin
 if not public.unimis_review_manager130(p_inst) then raise exception 'Academic review coordination required';end if;
 if p_mode='small' then stages:=array['department','central','final'];elsif p_mode='large' then stages:=array['department','faculty','audit','college','academic_board'];elsif p_mode='large_no_college' then stages:=array['department','faculty','audit','academic_board'];else raise exception 'Choose small or large institution workflow';end if;
 perform 1 from public.institutions where id=p_inst for update;
 if exists(select 1 from public.unimis_result_batches130 rb where rb.institution_id=p_inst and rb.stages<>array['projected'] and rb.status in ('review','ready','publishing')) then raise exception 'Complete or cancel open batches before changing the workflow';end if;
 insert into public.unimis_review_config130(institution_id,enabled,stages,updated_by,review_mode) values(p_inst,true,stages,auth.uid(),case when p_mode='projected' then 'projected' else 'panel' end)
 on conflict(institution_id) do update set enabled=true,review_mode=excluded.review_mode,stages=excluded.stages,updated_by=auth.uid(),updated_at=now();
end $$;
create or replace function public.unimis_projected_action133(p_inst uuid,p_period uuid,p_results uuid[],p_action text,p_reference text,p_date date,p_attendees text,p_minutes text)
returns integer language plpgsql security definer set search_path='' as $$
declare rid uuid;dep uuid;bid uuid;rec record;n int:=0;queue jsonb;
begin
 if not public.unimis_review_manager130(p_inst) then raise exception 'Academic review authority required';end if;
 if p_action is null or p_action not in ('approve','return','publish') or coalesce(cardinality(p_results),0)=0 then raise exception 'Choose results and a valid action';end if;
 perform 1 from public.institutions where id=p_inst for update;
 queue:=public.unimis_projected_candidates133(p_inst,p_period,case when p_action='publish' then 'approved' else 'submitted' end);
 for rid in select distinct unnest(p_results) loop
 -- Resolve each selection against the authorised current queue, not client scope.
 select x.department_id into dep from jsonb_to_recordset(queue) as x(result_id uuid,department_id uuid) where x.result_id=rid;
 if dep is null then raise exception 'Selected result changed, belongs to another semester/school, or is locked in panel review; reload results';end if;
 if p_action='publish' then
 if length(trim(coalesce(p_minutes,'')))<5 then raise exception 'Publication note required';end if;
 select b.id into bid from public.unimis_result_batches130 b join public.unimis_batch_results130 br on br.batch_id=b.id where br.result_id=rid and b.stages=array['projected'] and b.status='ready';
 if (select count(*) from public.unimis_batch_results130 where batch_id=bid)<>1 then raise exception 'This earlier projected meeting must be published from Previous Meetings as a whole';end if;
 perform public.unimis_publish_review130(bid,p_minutes);
 else
 bid:=public.unimis_create_projected_batch132(p_inst,dep,p_period,'Projected review '||coalesce(p_reference,'')||' · '||rid::text,array[rid]);
 perform public.unimis_projected_decision132(bid,p_reference,p_date,p_attendees,p_minutes,p_action);
 if p_action='return' then update public.course_results set remarks='Returned for correction ['||p_reference||']: '||p_minutes where id=rid;end if;
 end if;
 n:=n+1;
 end loop;
 return n;
end $$;
create or replace function public.unimis_lecturer_corrections133(p_offering uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not exists(select 1 from public.unimis_current_lecturer() me join public.course_lecturers cl on cl.institution_id=me.institution_id and cl.lecturer_profile_id=me.lecturer_profile_id where cl.course_offering_id=p_offering) then raise exception 'Allocated lecturer access required';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('student',concat_ws(' ',s.first_name,s.last_name),'student_number',s.student_number,'status',r.result_status,'note',h.notes,'date',h.action_at) order by h.action_at desc) from public.course_results r join public.students s on s.id=r.student_id and s.institution_id=r.institution_id join public.result_approval_history h on h.course_result_id=r.id and h.institution_id=r.institution_id where r.course_offering_id=p_offering and h.new_status='draft'),'[]'::jsonb);
end $$;
revoke all on function public.unimis_projected_candidates133(uuid,uuid,text) from public,anon;
grant execute on function public.unimis_projected_candidates133(uuid,uuid,text) to authenticated;
revoke all on function public.unimis_projected_action133(uuid,uuid,uuid[],text,text,date,text,text) from public,anon;
grant execute on function public.unimis_projected_action133(uuid,uuid,uuid[],text,text,date,text,text) to authenticated;
revoke all on function public.unimis_lecturer_corrections133(uuid) from public,anon;
grant execute on function public.unimis_lecturer_corrections133(uuid) to authenticated;
