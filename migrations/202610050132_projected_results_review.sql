alter table public.unimis_review_config130 add column if not exists review_mode text not null default 'panel' check(review_mode in ('panel','projected'));
create table if not exists public.unimis_projected_minutes132(
 batch_id uuid primary key references public.unimis_result_batches130(id),reference text not null,meeting_date date not null,attendees text not null,minutes text not null,decision text not null check(decision in ('approve','return')),recorded_by uuid not null references auth.users(id),recorded_at timestamptz not null default now());
alter table public.unimis_projected_minutes132 enable row level security;
revoke all on public.unimis_projected_minutes132 from public,anon,authenticated;
create or replace function public.unimis_save_review_config130(p_inst uuid,p_mode text)
returns void language plpgsql security definer set search_path='' as $$
declare stages text[];
begin
 if not public.unimis_review_manager130(p_inst) then raise exception 'Academic review coordination required';end if;
 if p_mode='projected' then stages:=array['projected'];elsif p_mode='small' then stages:=array['department','central','final'];elsif p_mode='large' then stages:=array['department','faculty','audit','college','academic_board'];elsif p_mode='large_no_college' then stages:=array['department','faculty','audit','academic_board'];else raise exception 'Choose small or large institution workflow';end if;
 perform 1 from public.institutions where id=p_inst for update;
 if exists(select 1 from public.unimis_result_batches130 where institution_id=p_inst and status in ('review','ready','publishing')) then raise exception 'Complete or cancel open batches before changing the workflow';end if;
 insert into public.unimis_review_config130(institution_id,enabled,stages,updated_by,review_mode) values(p_inst,true,stages,auth.uid(),case when p_mode='projected' then 'projected' else 'panel' end)
 on conflict(institution_id) do update set enabled=true,review_mode=excluded.review_mode,stages=excluded.stages,updated_by=auth.uid(),updated_at=now();
end $$;
create or replace function public.unimis_create_result_batch130(p_inst uuid,p_department uuid,p_period uuid,p_title text,p_committees uuid[])
returns uuid language plpgsql security definer set search_path='' as $$
declare cfg public.unimis_review_config130; c public.unimis_committees130; fid uuid; rid uuid;i int; n int;
begin
 if not public.unimis_review_manager130(p_inst) then raise exception 'Academic review coordination required';end if;
 perform 1 from public.institutions where id=p_inst for update;
 select * into cfg from public.unimis_review_config130 where institution_id=p_inst and enabled;
 if cfg.review_mode='projected' then raise exception 'Use the projected meeting workspace';end if;
 if cfg.institution_id is null then raise exception 'Enable a committee workflow first';end if;
 select faculty_id into fid from public.departments where id=p_department and institution_id=p_inst;
 if fid is null or not exists(select 1 from public.academic_periods where id=p_period and institution_id=p_inst) then raise exception 'Choose a school department and semester';end if;
 if length(trim(coalesce(p_title,'')))<3 or cardinality(p_committees) is distinct from cardinality(cfg.stages) then raise exception 'Title and one panel per review stage required';end if;
 for i in 1..cardinality(cfg.stages) loop
 select * into c from public.unimis_committees130 where id=p_committees[i] for update;
 if c.id is null or c.institution_id<>p_inst or c.stage<>cfg.stages[i] or c.stage='department' and c.department_id is distinct from p_department or c.stage='faculty' and c.faculty_id is distinct from fid then raise exception 'Panel scope does not match this batch';end if;
 if (select count(*) from public.unimis_panel_members130 where committee_id=c.id)<c.quorum or not exists(select 1 from public.unimis_panel_members130 where committee_id=c.id and responsibility='chair') or not exists(select 1 from public.unimis_panel_members130 where committee_id=c.id and responsibility='secretary') then raise exception 'Every panel needs a separate chair and secretary and enough members for quorum';end if;
 end loop;
 -- All non-dropped registered courses in the cohort need a recorded, submitted result.
 if exists(select 1 from public.student_course_registrations scr join public.student_period_registrations spr on spr.id=scr.period_registration_id and spr.institution_id=p_inst
 join public.student_programme_enrolments en on en.id=spr.programme_enrolment_id and en.institution_id=p_inst
 join public.programmes p on p.id=en.programme_id and p.institution_id=p_inst
 left join public.course_results cr on cr.student_course_registration_id=scr.id and cr.institution_id=p_inst
 where scr.institution_id=p_inst and spr.academic_period_id=p_period and p.department_id=p_department and scr.status not in ('dropped','withdrawn')
 and (cr.id is null or cr.student_id is distinct from scr.student_id or spr.student_id is distinct from scr.student_id or en.student_id is distinct from spr.student_id or cr.result_status not in ('submitted','approved','published') or cr.submitted_by is null or cr.grade_point is null or cr.letter_grade is null or cr.passed is null)) then raise exception 'Missing, draft, withheld or unsubmitted results must be resolved before creating the cohort batch';end if;
 perform cr.id from public.course_results cr join public.student_course_registrations scr on scr.id=cr.student_course_registration_id and scr.institution_id=p_inst
 join public.student_period_registrations spr on spr.id=scr.period_registration_id and spr.institution_id=p_inst
 join public.student_programme_enrolments en on en.id=spr.programme_enrolment_id and en.institution_id=p_inst join public.programmes p on p.id=en.programme_id and p.institution_id=p_inst
 where cr.institution_id=p_inst and spr.academic_period_id=p_period and p.department_id=p_department and scr.status not in ('dropped','withdrawn') and cr.result_status in ('submitted','approved') for update of cr;
 if exists(select 1 from public.unimis_batch_results130 br join public.unimis_result_batches130 b on b.id=br.batch_id join public.course_results cr on cr.id=br.result_id
 join public.student_course_registrations scr on scr.id=cr.student_course_registration_id join public.student_period_registrations spr on spr.id=scr.period_registration_id
 join public.student_programme_enrolments en on en.id=spr.programme_enrolment_id join public.programmes p on p.id=en.programme_id
 where cr.institution_id=p_inst and spr.academic_period_id=p_period and p.department_id=p_department and b.status in ('review','ready','publishing')) then raise exception 'These results already belong to an open review batch';end if;
 insert into public.unimis_result_batches130(institution_id,department_id,academic_period_id,title,stages,committees,created_by)
 values(p_inst,p_department,p_period,trim(p_title),cfg.stages,p_committees,auth.uid()) returning id into rid;
 insert into public.unimis_batch_results130(batch_id,result_id,snapshot)
 select rid,cr.id,jsonb_build_object('student_number',s.student_number,'student_name',concat_ws(' ',s.first_name,s.middle_name,s.last_name),'course_code',co.code,'course_name',co.name,'credits',co.credit_hours,'programme',p.code,'level',spr.level_number,
 'score',cr.total_score,'grade',cr.letter_grade,'grade_point',cr.grade_point,'quality_points',cr.quality_points,'passed',cr.passed,'submitted_by',cr.submitted_by,'initial_status',cr.result_status)
 from public.course_results cr join public.students s on s.id=cr.student_id and s.institution_id=p_inst
 join public.course_offerings off on off.id=cr.course_offering_id and off.institution_id=p_inst join public.courses co on co.id=off.course_id and co.institution_id=p_inst
 join public.student_course_registrations scr on scr.id=cr.student_course_registration_id and scr.institution_id=p_inst
 join public.student_period_registrations spr on spr.id=scr.period_registration_id and spr.institution_id=p_inst
 join public.student_programme_enrolments en on en.id=spr.programme_enrolment_id and en.institution_id=p_inst join public.programmes p on p.id=en.programme_id and p.institution_id=p_inst
 where cr.institution_id=p_inst and spr.academic_period_id=p_period and p.department_id=p_department and scr.status not in ('dropped','withdrawn') and cr.result_status in ('submitted','approved');
 get diagnostics n=row_count;if n=0 then raise exception 'No submitted results for this department and semester; historical published results are not re-reviewed';end if;
 insert into public.unimis_review_events130(batch_id,actor,action,note) values(rid,auth.uid(),'create_batch','Frozen snapshot: '||n||' results');return rid;
end $$;
create or replace function public.unimis_create_projected_batch132(p_inst uuid,p_department uuid,p_period uuid,p_title text,p_results uuid[])
returns uuid language plpgsql security definer set search_path='' as $$
declare cfg public.unimis_review_config130; c public.unimis_committees130; fid uuid; rid uuid;i int; n int;
begin
 if not public.unimis_review_manager130(p_inst) then raise exception 'Academic review coordination required';end if;
 perform 1 from public.institutions where id=p_inst for update;
 select * into cfg from public.unimis_review_config130 where institution_id=p_inst and enabled;
 if cfg.institution_id is null then raise exception 'Enable a committee workflow first';end if;
 select faculty_id into fid from public.departments where id=p_department and institution_id=p_inst;
 if fid is null or not exists(select 1 from public.academic_periods where id=p_period and institution_id=p_inst) then raise exception 'Choose a school department and semester';end if;
 if cfg.review_mode<>'projected' then raise exception 'Choose Projected Meeting mode first';end if;
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
create or replace function public.unimis_projected_candidates132(p_inst uuid,p_department uuid,p_period uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.unimis_review_manager130(p_inst) then raise exception 'Academic review coordination required';end if;
 return coalesce((select jsonb_agg(x.item) from ( select jsonb_build_object('result_id',cr.id)||jsonb_build_object('student_number',s.student_number,'student_name',concat_ws(' ',s.first_name,s.middle_name,s.last_name),'course_code',co.code,'course_name',co.name,'credits',co.credit_hours,'programme',p.code,'level',spr.level_number,
 'score',cr.total_score,'grade',cr.letter_grade,'grade_point',cr.grade_point,'quality_points',cr.quality_points,'passed',cr.passed,'submitted_by',cr.submitted_by,'initial_status',cr.result_status) item
 from public.course_results cr join public.students s on s.id=cr.student_id and s.institution_id=p_inst
 join public.course_offerings off on off.id=cr.course_offering_id and off.institution_id=p_inst join public.courses co on co.id=off.course_id and co.institution_id=p_inst
 join public.student_course_registrations scr on scr.id=cr.student_course_registration_id and scr.institution_id=p_inst
 join public.student_period_registrations spr on spr.id=scr.period_registration_id and spr.institution_id=p_inst
 join public.student_programme_enrolments en on en.id=spr.programme_enrolment_id and en.institution_id=p_inst join public.programmes p on p.id=en.programme_id and p.institution_id=p_inst
 where cr.institution_id=p_inst and spr.academic_period_id=p_period and p.department_id=p_department and scr.status not in ('dropped','withdrawn') and cr.result_status='submitted' and cr.submitted_by is not null and cr.total_score is not null and cr.grade_point is not null and cr.letter_grade is not null and cr.passed is not null and cr.student_id=scr.student_id and spr.student_id=scr.student_id and en.student_id=spr.student_id and not exists(select 1 from public.unimis_batch_results130 br join public.unimis_result_batches130 b on b.id=br.batch_id where br.result_id=cr.id and b.status in ('review','ready','publishing'))) x),'[]'::jsonb);
end $$;
create or replace function public.unimis_projected_decision132(p_batch uuid,p_reference text,p_date date,p_attendees text,p_minutes text,p_decision text)
returns void language plpgsql security definer set search_path='' as $$
declare b public.unimis_result_batches130;rr record;
begin
 select * into b from public.unimis_result_batches130 where id=p_batch for update;
 if b.id is null or not public.unimis_review_manager130(b.institution_id) then raise exception 'Academic review authority required';end if;
 if b.stages<>array['projected'] or b.status<>'review' then raise exception 'An open projected meeting batch is required';end if;
 if length(trim(coalesce(p_reference,'')))<3 or p_date is null or p_date>current_date or length(trim(coalesce(p_attendees,'')))<5 or length(trim(coalesce(p_minutes,'')))<10 or p_decision not in ('approve','return') or p_decision is null then raise exception 'Meeting reference, date, attendees, minutes and decision required';end if;
 if p_decision='approve' and exists(select 1 from public.unimis_batch_results130 br join public.course_results r on r.id=br.result_id where br.batch_id=b.id and (r.submitted_by=auth.uid() or exists(select 1 from public.assessment_scores sc where sc.student_course_registration_id=r.student_course_registration_id and sc.entered_by=auth.uid()))) then raise exception 'You cannot approve results you prepared';end if;
 insert into public.unimis_projected_minutes132 values(b.id,trim(p_reference),p_date,trim(p_attendees),trim(p_minutes),p_decision,auth.uid(),now());
 if p_decision='approve' then
 update public.unimis_result_batches130 set status='publishing' where id=b.id;
 for rr in select r.* from public.course_results r join public.unimis_batch_results130 br on br.result_id=r.id where br.batch_id=b.id for update of r loop
 update public.course_results set result_status='approved',approved_by=auth.uid(),approved_at=now(),updated_at=now() where id=rr.id;
 insert into public.result_approval_history(institution_id,course_result_id,old_status,new_status,action_by,action_at,notes) values(b.institution_id,rr.id,rr.result_status,'approved',auth.uid(),now(),'Projected meeting '||p_reference||': '||p_minutes);
 end loop;
 update public.unimis_result_batches130 set status='ready' where id=b.id;
 else
 update public.unimis_result_batches130 set status='returned' where id=b.id;
 for rr in select r.* from public.course_results r join public.unimis_batch_results130 br on br.result_id=r.id where br.batch_id=b.id for update of r loop
 update public.course_results set result_status='draft',approved_by=null,approved_at=null,updated_at=now() where id=rr.id;
 insert into public.result_approval_history(institution_id,course_result_id,old_status,new_status,action_by,action_at,notes) values(b.institution_id,rr.id,rr.result_status,'draft',auth.uid(),now(),'Returned at projected meeting '||p_reference||': '||p_minutes);
 end loop;
 end if;
 insert into public.unimis_review_events130(batch_id,actor,action,note) values(b.id,auth.uid(),'projected_'||p_decision,p_reference||': '||p_minutes);
end $$;
create or replace function public.unimis_projected_record132(p_batch uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.unimis_batch_access130(p_batch) then raise exception 'Batch access denied';end if;
 return (select to_jsonb(m) from public.unimis_projected_minutes132 m where batch_id=p_batch);
end $$;

create or replace function public.unimis_publish_review130(p_batch uuid,p_note text)
returns void language plpgsql security definer set search_path='' as $$
declare b public.unimis_result_batches130;cr record;g record;
begin
 select * into b from public.unimis_result_batches130 where id=p_batch for update;
 if b.id is null or not public.unimis_review_manager130(b.institution_id) then raise exception 'Academic publication authority required';end if;
 if b.status<>'ready' or length(trim(coalesce(p_note,'')))<5 then raise exception 'Every committee stage must be confirmed before publication';end if;
 if b.stages<>array['projected'] and (select count(*) from public.unimis_review_meetings130 where batch_id=b.id and resolution='approve' and confirmed_at is not null)<>cardinality(b.stages) then raise exception 'Missing confirmed committee approvals';end if;
 if b.stages=array['projected'] and not exists(select 1 from public.unimis_projected_minutes132 where batch_id=b.id and decision='approve') then raise exception 'Recorded projected meeting approval required';end if;
 if exists(select 1 from public.unimis_batch_results130 br join public.course_results r on r.id=br.result_id where br.batch_id=b.id and (r.result_status not in ('submitted','approved') or r.total_score is distinct from (br.snapshot->>'score')::numeric or r.letter_grade is distinct from br.snapshot->>'grade' or r.grade_point is distinct from (br.snapshot->>'grade_point')::numeric or r.quality_points is distinct from (br.snapshot->>'quality_points')::numeric or r.submitted_by is distinct from (br.snapshot->>'submitted_by')::uuid)) then raise exception 'The reviewed version changed; create a fresh batch';end if;
 if b.stages<>array['projected'] and exists(select 1 from public.student_course_registrations scr join public.student_period_registrations spr on spr.id=scr.period_registration_id and spr.institution_id=b.institution_id
 join public.student_programme_enrolments en on en.id=spr.programme_enrolment_id and en.institution_id=b.institution_id join public.programmes p on p.id=en.programme_id and p.institution_id=b.institution_id
 left join public.course_results r on r.student_course_registration_id=scr.id and r.institution_id=b.institution_id
 where scr.institution_id=b.institution_id and spr.academic_period_id=b.academic_period_id and p.department_id=b.department_id and scr.status not in ('dropped','withdrawn')
 and (r.id is null or r.result_status<>'published' and not exists(select 1 from public.unimis_batch_results130 br where br.batch_id=b.id and br.result_id=r.id))) then raise exception 'Cohort registration changed or results are missing; create a fresh review batch';end if;
 if exists(select 1 from public.unimis_batch_results130 br join public.course_results rr on rr.id=br.result_id
 left join public.student_course_registrations scr on scr.id=rr.student_course_registration_id left join public.student_period_registrations spr on spr.id=scr.period_registration_id
 left join public.student_programme_enrolments en on en.id=spr.programme_enrolment_id left join public.programmes p on p.id=en.programme_id
 left join public.course_offerings off on off.id=rr.course_offering_id left join public.courses c on c.id=off.course_id
 where br.batch_id=b.id and (c.id is null or c.credit_hours is distinct from (br.snapshot->>'credits')::numeric or c.code is distinct from br.snapshot->>'course_code'
 or p.department_id is distinct from b.department_id or p.code is distinct from br.snapshot->>'programme' or spr.academic_period_id is distinct from b.academic_period_id or spr.level_number is distinct from (br.snapshot->>'level')::int)) then raise exception 'Course credits, programme or cohort scope changed; restart review';end if;
 update public.unimis_result_batches130 set status='publishing' where id=b.id;
 for cr in select r.* from public.course_results r join public.unimis_batch_results130 br on br.result_id=r.id where br.batch_id=b.id for update of r loop
 if cr.result_status='submitted' then
 update public.course_results set result_status='approved',approved_by=auth.uid(),approved_at=now(),updated_at=now() where id=cr.id;
 insert into public.result_approval_history(institution_id,course_result_id,old_status,new_status,action_by,action_at,notes) values(b.institution_id,cr.id,'submitted','approved',auth.uid(),now(),'Committee stages confirmed: '||p_note);end if;
 update public.course_results set result_status='published',published_at=now(),updated_at=now() where id=cr.id;
 insert into public.result_approval_history(institution_id,course_result_id,old_status,new_status,action_by,action_at,notes) values(b.institution_id,cr.id,'approved','published',auth.uid(),now(),p_note);
 end loop;
 -- Refresh semester GPA/CGPA records from published results only, including later semesters affected by earlier publication.
 for g in select distinct r.student_id,off.academic_period_id from public.course_results r
 join public.course_offerings off on off.id=r.course_offering_id and off.institution_id=b.institution_id
 where r.institution_id=b.institution_id and r.result_status='published' and r.student_id in(
 select rr.student_id from public.unimis_batch_results130 br join public.course_results rr on rr.id=br.result_id where br.batch_id=b.id) loop
 insert into public.student_period_results(institution_id,student_id,academic_period_id,attempted_credits,earned_credits,total_quality_points,gpa,cgpa,status,calculated_at,approved_by,approved_at)
 select b.institution_id,g.student_id,g.academic_period_id,coalesce(sum(c.credit_hours),0),coalesce(sum(case when r.passed then c.credit_hours else 0 end),0),coalesce(sum(c.credit_hours*coalesce(r.grade_point,0)),0),
 round(sum(c.credit_hours*coalesce(r.grade_point,0))/nullif(sum(c.credit_hours),0),3),
 (select round(sum(c2.credit_hours*coalesce(r2.grade_point,0))/nullif(sum(c2.credit_hours),0),3)
 from public.course_results r2 join public.course_offerings o2 on o2.id=r2.course_offering_id and o2.institution_id=b.institution_id join public.courses c2 on c2.id=o2.course_id and c2.institution_id=b.institution_id join public.academic_periods ap2 on ap2.id=o2.academic_period_id
 where r2.institution_id=b.institution_id and r2.student_id=g.student_id and r2.result_status='published' and ap2.start_date<=(select start_date from public.academic_periods where id=g.academic_period_id)),
 'published',now(),auth.uid(),now()
 from public.course_results r join public.course_offerings off on off.id=r.course_offering_id and off.institution_id=b.institution_id join public.courses c on c.id=off.course_id and c.institution_id=b.institution_id
 where r.institution_id=b.institution_id and r.student_id=g.student_id and off.academic_period_id=g.academic_period_id and r.result_status='published'
 on conflict(student_id,academic_period_id) do update set attempted_credits=excluded.attempted_credits,earned_credits=excluded.earned_credits,total_quality_points=excluded.total_quality_points,gpa=excluded.gpa,cgpa=excluded.cgpa,status='published',calculated_at=now(),approved_by=auth.uid(),approved_at=now(),updated_at=now();
 end loop;
 update public.unimis_result_batches130 set status='published' where id=b.id;
 insert into public.unimis_review_events130(batch_id,actor,action,note) values(b.id,auth.uid(),'publish',trim(p_note));
end $$;
revoke all on function public.unimis_projected_candidates132(uuid,uuid,uuid) from public,anon;
grant execute on function public.unimis_projected_candidates132(uuid,uuid,uuid) to authenticated;
revoke all on function public.unimis_create_projected_batch132(uuid,uuid,uuid,text,uuid[]) from public,anon;
grant execute on function public.unimis_create_projected_batch132(uuid,uuid,uuid,text,uuid[]) to authenticated;
revoke all on function public.unimis_projected_decision132(uuid,text,date,text,text,text) from public,anon;
grant execute on function public.unimis_projected_decision132(uuid,text,date,text,text,text) to authenticated;
revoke all on function public.unimis_projected_record132(uuid) from public,anon;
grant execute on function public.unimis_projected_record132(uuid) to authenticated;
