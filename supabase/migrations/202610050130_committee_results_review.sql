-- Committee responsibility is scoped and separate from institutional roles.
insert into public.roles(name,code,is_system_role,is_active)
select 'Academic Panel','academic_panel',true,true where not exists(select 1 from public.roles where code='academic_panel' and institution_id is null);
create table if not exists public.unimis_review_config130(
 institution_id uuid primary key references public.institutions(id),enabled boolean not null default false,
 stages text[] not null default array['department','central','final'],updated_by uuid references auth.users(id),updated_at timestamptz not null default now());
create table if not exists public.unimis_committees130(
 id uuid primary key default gen_random_uuid(),institution_id uuid not null references public.institutions(id),
 name text not null,stage text not null check(stage in ('department','faculty','audit','college','academic_board','central','final')),
 department_id uuid references public.departments(id),faculty_id uuid references public.faculties(id),quorum int not null check(quorum>=2),created_by uuid not null references auth.users(id),created_at timestamptz not null default now());
create table if not exists public.unimis_panel_members130(
 committee_id uuid references public.unimis_committees130(id),user_id uuid references auth.users(id),
 responsibility text not null check(responsibility in ('chair','secretary','member')),assigned_by uuid references auth.users(id),assigned_at timestamptz not null default now(),primary key(committee_id,user_id));
create table if not exists public.unimis_panel_audit130(
 id uuid primary key default gen_random_uuid(),committee_id uuid not null references public.unimis_committees130(id),user_id uuid not null references auth.users(id),
 actor uuid not null references auth.users(id),action text not null,created_at timestamptz not null default now());
create unique index if not exists unimis_panel_officer130 on public.unimis_panel_members130(committee_id,responsibility) where responsibility in ('chair','secretary');
create table if not exists public.unimis_result_batches130(
 id uuid primary key default gen_random_uuid(),institution_id uuid not null references public.institutions(id),
 department_id uuid not null references public.departments(id),academic_period_id uuid not null references public.academic_periods(id),
 title text not null,stages text[] not null,committees uuid[] not null,stage_index int not null default 1,
 status text not null default 'review' check(status in ('review','ready','publishing','published','returned','deferred','cancelled')),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now());
create table if not exists public.unimis_batch_results130(
 batch_id uuid references public.unimis_result_batches130(id),result_id uuid references public.course_results(id) on delete restrict,
 snapshot jsonb not null,primary key(batch_id,result_id));
create index if not exists unimis_batch_result_lookup130 on public.unimis_batch_results130(result_id);
create table if not exists public.unimis_review_meetings130(
 id uuid primary key default gen_random_uuid(),batch_id uuid not null references public.unimis_result_batches130(id),stage_index int not null,
 committee_id uuid not null references public.unimis_committees130(id),reference text not null,meeting_date date not null,
 attendees uuid[] not null,membership_snapshot jsonb not null,resolution text not null check(resolution in ('approve','return','defer')),
 minutes text not null,recorded_by uuid not null references auth.users(id),recorded_at timestamptz not null default now(),
 confirmed_by uuid references auth.users(id),confirmed_at timestamptz,chair_note text,
 unique(batch_id,stage_index));
create table if not exists public.unimis_review_comments130(
 id uuid primary key default gen_random_uuid(),batch_id uuid not null references public.unimis_result_batches130(id),
 author uuid not null references auth.users(id),comment text not null,created_at timestamptz not null default now());
create table if not exists public.unimis_review_events130(
 id uuid primary key default gen_random_uuid(),batch_id uuid not null references public.unimis_result_batches130(id),
 actor uuid not null references auth.users(id),action text not null,note text not null,created_at timestamptz not null default now());
do $$declare t text;begin
 foreach t in array array['unimis_review_config130','unimis_committees130','unimis_panel_members130','unimis_panel_audit130','unimis_result_batches130','unimis_batch_results130','unimis_review_meetings130','unimis_review_comments130','unimis_review_events130'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t);end loop;
end $$;
create or replace function public.unimis_review_manager130(p_inst uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.unimis_effective_memberships116 m join public.roles r on r.id=m.role_id
 where m.user_id=auth.uid() and m.institution_id=p_inst and m.status='active' and r.is_active and r.code in ('owner','registrar','exam_officer'))
$$;
create or replace function public.unimis_batch_access130(p_batch uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.unimis_result_batches130 b where b.id=p_batch and
 (public.unimis_review_manager130(b.institution_id) or exists(
 select 1 from public.unimis_panel_members130 pm join public.institution_users m on m.user_id=pm.user_id and m.institution_id=b.institution_id
 join public.roles r on r.id=m.role_id and r.is_active where pm.user_id=auth.uid() and pm.committee_id=any(b.committees) and m.status='active')))
$$;
create or replace function public.unimis_review_setup130(p_inst uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.unimis_review_manager130(p_inst) then raise exception 'Academic review coordination required';end if;
 return jsonb_build_object('config',coalesce((select to_jsonb(c) from public.unimis_review_config130 c where institution_id=p_inst),jsonb_build_object('enabled',false,'stages',array['department','central','final'])),
 'appointment_history',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc) from public.unimis_panel_audit130 a join public.unimis_committees130 c on c.id=a.committee_id where c.institution_id=p_inst),'[]'::jsonb),
 'committees',coalesce((select jsonb_agg(to_jsonb(c)||jsonb_build_object('members',coalesce((select jsonb_agg(to_jsonb(pm)) from public.unimis_panel_members130 pm where pm.committee_id=c.id),'[]'::jsonb))) from public.unimis_committees130 c where c.institution_id=p_inst),'[]'::jsonb),
 'departments',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'faculty_id',faculty_id)) from public.departments where institution_id=p_inst),'[]'::jsonb),
 'faculties',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name)) from public.faculties where institution_id=p_inst),'[]'::jsonb),
 'periods',coalesce((select jsonb_agg(jsonb_build_object('id',ap.id,'name',ay.name||' • '||ap.name) order by ay.start_date desc,ap.period_number) from public.academic_periods ap join public.academic_years ay on ay.id=ap.academic_year_id where ap.institution_id=p_inst),'[]'::jsonb),
 'staff',coalesce((select jsonb_agg(jsonb_build_object('user_id',m.user_id,'name',coalesce(p.display_name,u.email),'email',u.email,'role',r.code)) from public.institution_users m join public.roles r on r.id=m.role_id join auth.users u on u.id=m.user_id left join public.profiles p on p.id=m.user_id where m.institution_id=p_inst and m.status='active' and r.is_active and r.code not in ('student','parent','auditor','superadmin','super_admin','platform_superadmin','academic_panel')),'[]'::jsonb));
end $$;
create or replace function public.unimis_save_review_config130(p_inst uuid,p_mode text)
returns void language plpgsql security definer set search_path='' as $$
declare stages text[];
begin
 if not public.unimis_review_manager130(p_inst) then raise exception 'Academic review coordination required';end if;
 if p_mode='small' then stages:=array['department','central','final'];elsif p_mode='large' then stages:=array['department','faculty','audit','college','academic_board'];elsif p_mode='large_no_college' then stages:=array['department','faculty','audit','academic_board'];else raise exception 'Choose small or large institution workflow';end if;
 perform 1 from public.institutions where id=p_inst for update;
 if exists(select 1 from public.unimis_result_batches130 where institution_id=p_inst and status in ('review','ready','publishing')) then raise exception 'Complete or cancel open batches before changing the workflow';end if;
 insert into public.unimis_review_config130(institution_id,enabled,stages,updated_by) values(p_inst,true,stages,auth.uid())
 on conflict(institution_id) do update set enabled=true,stages=excluded.stages,updated_by=auth.uid(),updated_at=now();
end $$;
create or replace function public.unimis_create_committee130(p_inst uuid,p_name text,p_stage text,p_department uuid,p_faculty uuid,p_quorum int)
returns uuid language plpgsql security definer set search_path='' as $$
declare rid uuid;
begin
 if not public.unimis_review_manager130(p_inst) then raise exception 'Academic review coordination required';end if;
 if length(trim(coalesce(p_name,'')))<3 or p_quorum is null or p_quorum<2 then raise exception 'Committee name and quorum of at least two required';end if;
 if p_stage='department' then
 if p_faculty is not null or not exists(select 1 from public.departments where id=p_department and institution_id=p_inst) then raise exception 'Choose a department within this school';end if;
 elsif p_stage='faculty' then
 if p_department is not null or not exists(select 1 from public.faculties where id=p_faculty and institution_id=p_inst) then raise exception 'Choose a faculty within this school';end if;
 elsif p_stage in ('audit','college','academic_board','central','final') then
 if p_department is not null or p_faculty is not null then raise exception 'This stage uses explicitly assigned school batches';end if;
 else raise exception 'Invalid review stage';end if;
 insert into public.unimis_committees130(institution_id,name,stage,department_id,faculty_id,quorum,created_by)
 values(p_inst,trim(p_name),p_stage,p_department,p_faculty,p_quorum,auth.uid()) returning id into rid;return rid;
end $$;
create or replace function public.unimis_assign_panel_member130(p_committee uuid,p_user uuid,p_responsibility text)
returns void language plpgsql security definer set search_path='' as $$
declare c public.unimis_committees130;
begin
 select * into c from public.unimis_committees130 where id=p_committee for update;
 if c.id is null or not public.unimis_review_manager130(c.institution_id) then raise exception 'Academic review coordination required';end if;
 if exists(select 1 from public.unimis_result_batches130 where p_committee=any(committees) and status in ('review','ready','publishing')) then raise exception 'Panel membership is frozen for open batches';end if;
 if not exists(select 1 from public.institution_users m join public.roles r on r.id=m.role_id where m.user_id=p_user and m.institution_id=c.institution_id and m.status='active' and r.is_active and r.code not in ('student','parent','auditor','superadmin','super_admin','platform_superadmin','academic_panel')) then raise exception 'Choose an active staff member in this school';end if;
 if p_responsibility='remove' then insert into public.unimis_panel_audit130(committee_id,user_id,actor,action) values(c.id,p_user,auth.uid(),'remove');delete from public.unimis_panel_members130 where committee_id=c.id and user_id=p_user;return;end if;
 if p_responsibility not in ('chair','secretary','member') then raise exception 'Invalid panel responsibility';end if;
 insert into public.unimis_panel_members130(committee_id,user_id,responsibility,assigned_by) values(c.id,p_user,p_responsibility,auth.uid())
 on conflict(committee_id,user_id) do update set responsibility=excluded.responsibility,assigned_by=auth.uid(),assigned_at=now();
 insert into public.unimis_panel_audit130(committee_id,user_id,actor,action) values(c.id,p_user,auth.uid(),p_responsibility);
end $$;
-- Cohorts use the programme attached to the student's semester registration, not a current enrolment guess.
create or replace function public.unimis_create_result_batch130(p_inst uuid,p_department uuid,p_period uuid,p_title text,p_committees uuid[])
returns uuid language plpgsql security definer set search_path='' as $$
declare cfg public.unimis_review_config130; c public.unimis_committees130; fid uuid; rid uuid;i int; n int;
begin
 if not public.unimis_review_manager130(p_inst) then raise exception 'Academic review coordination required';end if;
 perform 1 from public.institutions where id=p_inst for update;
 select * into cfg from public.unimis_review_config130 where institution_id=p_inst and enabled;
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
create or replace function public.unimis_review_batches130(p_inst uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not exists(select 1 from public.institution_users where user_id=auth.uid() and institution_id=p_inst and status='active') then raise exception 'Active school membership required';end if;
 return coalesce((select jsonb_agg(to_jsonb(b)||jsonb_build_object('department',d.name,'period',y.name||' • '||ap.name) order by b.created_at desc)
 from public.unimis_result_batches130 b join public.departments d on d.id=b.department_id join public.academic_periods ap on ap.id=b.academic_period_id join public.academic_years y on y.id=ap.academic_year_id
 where b.institution_id=p_inst and public.unimis_batch_access130(b.id)),'[]'::jsonb);
end $$;
create or replace function public.unimis_review_batch130(p_batch uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare b public.unimis_result_batches130;
begin
 if not public.unimis_batch_access130(p_batch) then raise exception 'This review batch is outside your assigned scope';end if;
 select * into b from public.unimis_result_batches130 where id=p_batch;
 return jsonb_build_object('batch',to_jsonb(b),'manager',public.unimis_review_manager130(b.institution_id),
 'results',coalesce((select jsonb_agg(snapshot||jsonb_build_object('result_id',result_id) order by snapshot->>'programme',snapshot->>'level',snapshot->>'student_number',snapshot->>'course_code') from public.unimis_batch_results130 where batch_id=b.id),'[]'::jsonb),
 'panels',coalesce((select jsonb_agg(to_jsonb(c)||jsonb_build_object('members',coalesce((select jsonb_agg(to_jsonb(m)||jsonb_build_object('name',coalesce(p.display_name,u.email),'email',u.email,'active',coalesce(iu.status='active',false))) from public.unimis_panel_members130 m join auth.users u on u.id=m.user_id left join public.profiles p on p.id=m.user_id left join public.institution_users iu on iu.user_id=m.user_id and iu.institution_id=b.institution_id where m.committee_id=c.id),'[]'::jsonb))) from public.unimis_committees130 c where c.id=any(b.committees)),'[]'::jsonb),
 'meetings',coalesce((select jsonb_agg(to_jsonb(m) order by m.stage_index) from public.unimis_review_meetings130 m where m.batch_id=b.id),'[]'::jsonb),
 'comments',coalesce((select jsonb_agg(to_jsonb(c)||jsonb_build_object('author_email',u.email) order by c.created_at) from public.unimis_review_comments130 c join auth.users u on u.id=c.author where c.batch_id=b.id),'[]'::jsonb),
 'events',coalesce((select jsonb_agg(to_jsonb(e)||jsonb_build_object('actor_email',u.email) order by e.created_at) from public.unimis_review_events130 e join auth.users u on u.id=e.actor where e.batch_id=b.id),'[]'::jsonb));
end $$;
create or replace function public.unimis_comment_review130(p_batch uuid,p_comment text)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.unimis_batch_access130(p_batch) then raise exception 'Review scope required';end if;
 if length(trim(coalesce(p_comment,'')))<5 then raise exception 'Write a useful review comment';end if;
 insert into public.unimis_review_comments130(batch_id,author,comment) values(p_batch,auth.uid(),trim(p_comment));
end $$;
create or replace function public.unimis_record_meeting130(p_batch uuid,p_reference text,p_date date,p_attendees uuid[],p_resolution text,p_minutes text)
returns void language plpgsql security definer set search_path='' as $$
declare b public.unimis_result_batches130;c public.unimis_committees130;n int;chair uuid;
begin
 select * into b from public.unimis_result_batches130 where id=p_batch for update;
 if b.id is null or not public.unimis_batch_access130(b.id) then raise exception 'Review scope required';end if;
 if b.status<>'review' then raise exception 'This batch is not awaiting review';end if;
 select * into c from public.unimis_committees130 where id=b.committees[b.stage_index];
 if not exists(select 1 from public.unimis_panel_members130 where committee_id=c.id and user_id=auth.uid() and responsibility='secretary') then raise exception 'Only the assigned secretary can record this meeting';end if;
 select user_id into chair from public.unimis_panel_members130 where committee_id=c.id and responsibility='chair';
 if length(trim(coalesce(p_reference,'')))<3 or p_date is null or p_date>current_date or length(trim(coalesce(p_minutes,'')))<10 or p_resolution not in ('approve','return','defer') or p_resolution is null then raise exception 'Meeting reference, date, resolution and substantive minutes required';end if;
 if p_attendees is null or cardinality(p_attendees)<c.quorum or not (auth.uid()=any(p_attendees)) or not(chair=any(p_attendees)) then raise exception 'Quorum, chair and secretary attendance required';end if;
 select count(distinct pm.user_id) into n from public.unimis_panel_members130 pm join public.institution_users m on m.user_id=pm.user_id and m.institution_id=b.institution_id and m.status='active' join public.roles r on r.id=m.role_id and r.is_active where pm.committee_id=c.id and pm.user_id=any(p_attendees);
 if n<>cardinality(p_attendees) then raise exception 'Attendance must contain distinct active panel members only';end if;
 insert into public.unimis_review_meetings130(batch_id,stage_index,committee_id,reference,meeting_date,attendees,membership_snapshot,resolution,minutes,recorded_by)
 values(b.id,b.stage_index,c.id,trim(p_reference),p_date,p_attendees,(select jsonb_agg(to_jsonb(pm)) from public.unimis_panel_members130 pm where committee_id=c.id),p_resolution,trim(p_minutes),auth.uid())
 on conflict(batch_id,stage_index) do update set reference=excluded.reference,meeting_date=excluded.meeting_date,attendees=excluded.attendees,membership_snapshot=excluded.membership_snapshot,resolution=excluded.resolution,minutes=excluded.minutes,recorded_at=now()
 where public.unimis_review_meetings130.confirmed_at is null;
 insert into public.unimis_review_events130(batch_id,actor,action,note) values(b.id,auth.uid(),'record_meeting',trim(p_reference)||': '||p_resolution);
end $$;
create or replace function public.unimis_confirm_meeting130(p_batch uuid,p_note text)
returns void language plpgsql security definer set search_path='' as $$
declare b public.unimis_result_batches130;m public.unimis_review_meetings130;
begin
 select * into b from public.unimis_result_batches130 where id=p_batch for update;
 if b.id is null or not public.unimis_batch_access130(b.id) then raise exception 'Review scope required';end if;
 if b.status<>'review' then raise exception 'This batch is not awaiting review';end if;
 if not exists(select 1 from public.unimis_panel_members130 where committee_id=b.committees[b.stage_index] and user_id=auth.uid() and responsibility='chair') then raise exception 'Only the assigned chair can confirm this stage';end if;
 select * into m from public.unimis_review_meetings130 where batch_id=b.id and stage_index=b.stage_index for update;
 if m.id is null or m.confirmed_at is not null or m.recorded_by=auth.uid() or length(trim(coalesce(p_note,'')))<5 then raise exception 'An independent secretary record and chair decision note required';end if;
 if m.resolution='approve' and exists(select 1 from public.unimis_batch_results130 br join public.course_results cr on cr.id=br.result_id where br.batch_id=b.id and (cr.submitted_by=auth.uid() or exists(select 1 from public.assessment_scores x where x.student_course_registration_id=cr.student_course_registration_id and x.entered_by=auth.uid()))) then raise exception 'The result preparer cannot confirm approval of their own batch';end if;
 -- Revalidate attendance after suspensions and before confirmation.
 if (select count(*) from public.institution_users iu join public.roles r on r.id=iu.role_id and r.is_active where iu.institution_id=b.institution_id and iu.status='active' and iu.user_id=any(m.attendees))<>cardinality(m.attendees) then raise exception 'Recorded attendees are no longer all active';end if;
 update public.unimis_review_meetings130 set confirmed_by=auth.uid(),confirmed_at=now(),chair_note=trim(p_note) where id=m.id;
 if m.resolution='approve' then
 if b.stage_index=cardinality(b.stages) then update public.unimis_result_batches130 set status='ready' where id=b.id;
 else update public.unimis_result_batches130 set stage_index=stage_index+1 where id=b.id;end if;
 elsif m.resolution='return' then
 update public.unimis_result_batches130 set status='returned' where id=b.id;
 update public.course_results cr set result_status='draft',approved_by=null,approved_at=null,remarks='Committee return: '||m.minutes,updated_at=now() where id in(select result_id from public.unimis_batch_results130 where batch_id=b.id);
 insert into public.result_approval_history(institution_id,course_result_id,old_status,new_status,action_by,action_at,notes)
 select b.institution_id,br.result_id,br.snapshot->>'initial_status','draft',auth.uid(),now(),'Committee return: '||m.minutes from public.unimis_batch_results130 br where br.batch_id=b.id;
 else
 -- Deferred snapshots remain historical; a fresh batch will restart all stages.
 update public.unimis_result_batches130 set status='deferred' where id=b.id;
 end if;
 insert into public.unimis_review_events130(batch_id,actor,action,note) values(b.id,auth.uid(),'confirm_'||m.resolution,trim(p_note));
end $$;
create or replace function public.unimis_cancel_review130(p_batch uuid,p_note text)
returns void language plpgsql security definer set search_path='' as $$
declare b public.unimis_result_batches130;
begin
 select * into b from public.unimis_result_batches130 where id=p_batch for update;
 if b.id is null or not public.unimis_review_manager130(b.institution_id) then raise exception 'Academic review coordination required';end if;
 if b.status not in ('review','ready') or length(trim(coalesce(p_note,'')))<10 then raise exception 'Only open batches can be cancelled with a substantive reason';end if;
 update public.unimis_result_batches130 set status='cancelled' where id=b.id;
 insert into public.unimis_review_events130(batch_id,actor,action,note) values(b.id,auth.uid(),'cancel',trim(p_note));
end $$;
-- Freeze all result values; no legacy approval or direct write may bypass the committee gate.
create or replace function public.unimis_guard_committee_result130()
returns trigger language plpgsql security definer set search_path='' as $$
declare b public.unimis_result_batches130;inst uuid;
begin
 if tg_op='DELETE' then inst:=old.institution_id;else inst:=new.institution_id;end if;
 select batch.* into b from public.unimis_batch_results130 br join public.unimis_result_batches130 batch on batch.id=br.batch_id
 where br.result_id=old.id and batch.status in ('review','ready','publishing') limit 1;
 if tg_op='DELETE' and old.result_status='published' then raise exception 'Published results cannot be deleted';end if;
 if tg_op='UPDATE' and old.result_status='published' and (to_jsonb(new)-array['updated_at','remarks']) is distinct from (to_jsonb(old)-array['updated_at','remarks']) then raise exception 'Published results are locked; an authorised correction workflow is required';end if;
 if b.id is not null then
 if tg_op='DELETE' then raise exception 'Results in a committee batch cannot be deleted';end if;
 if b.status<>'publishing' and (to_jsonb(new)-'updated_at') is distinct from (to_jsonb(old)-'updated_at') then raise exception 'Results are frozen in a committee batch; return them for correction';end if;
 if (to_jsonb(new)-array['result_status','approved_by','approved_at','published_at','updated_at','remarks']) is distinct from (to_jsonb(old)-array['result_status','approved_by','approved_at','published_at','updated_at','remarks']) then raise exception 'Results are frozen in a committee batch; return them for correction';end if;
 if new.result_status is distinct from old.result_status and (b.status<>'publishing' or not public.unimis_review_manager130(inst)) then raise exception 'Complete the committee workflow before changing result status';end if;
 end if;
 if tg_op='UPDATE' and new.result_status in ('approved','published') and new.result_status is distinct from old.result_status and exists(select 1 from public.unimis_review_config130 where institution_id=inst and enabled) and (b.id is null or b.status<>'publishing' or not public.unimis_review_manager130(inst)) then raise exception 'Committee approval and authorised publication required';end if;
 if tg_op='DELETE' then return old;else return new;end if;
end $$;
drop trigger if exists unimis_committee_result_guard130 on public.course_results;
create trigger unimis_committee_result_guard130 before update or delete on public.course_results for each row execute function public.unimis_guard_committee_result130();
create or replace function public.unimis_publish_review130(p_batch uuid,p_note text)
returns void language plpgsql security definer set search_path='' as $$
declare b public.unimis_result_batches130;cr record;g record;
begin
 select * into b from public.unimis_result_batches130 where id=p_batch for update;
 if b.id is null or not public.unimis_review_manager130(b.institution_id) then raise exception 'Academic publication authority required';end if;
 if b.status<>'ready' or length(trim(coalesce(p_note,'')))<5 then raise exception 'Every committee stage must be confirmed before publication';end if;
 if (select count(*) from public.unimis_review_meetings130 where batch_id=b.id and resolution='approve' and confirmed_at is not null)<>cardinality(b.stages) then raise exception 'Missing confirmed committee approvals';end if;
 if exists(select 1 from public.unimis_batch_results130 br join public.course_results r on r.id=br.result_id where br.batch_id=b.id and (r.result_status not in ('submitted','approved') or r.total_score is distinct from (br.snapshot->>'score')::numeric or r.letter_grade is distinct from br.snapshot->>'grade' or r.grade_point is distinct from (br.snapshot->>'grade_point')::numeric or r.quality_points is distinct from (br.snapshot->>'quality_points')::numeric or r.submitted_by is distinct from (br.snapshot->>'submitted_by')::uuid)) then raise exception 'The reviewed version changed; create a fresh batch';end if;
 if exists(select 1 from public.student_course_registrations scr join public.student_period_registrations spr on spr.id=scr.period_registration_id and spr.institution_id=b.institution_id
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
create or replace function public.unimis_my_panel_roles130()
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('institution_id',x.institution_id,'role_id',r.id,'role',jsonb_build_object('id',r.id,'name',r.name,'code',r.code,'is_active',r.is_active))),'[]'::jsonb)
 from (select distinct m.institution_id from public.unimis_panel_members130 pm join public.unimis_committees130 c on c.id=pm.committee_id join public.institution_users m on m.user_id=pm.user_id and m.institution_id=c.institution_id join public.roles mr on mr.id=m.role_id and mr.is_active where pm.user_id=auth.uid() and m.status='active') x
 join public.roles r on r.code='academic_panel' and r.institution_id is null and r.is_active
$$;
-- The panel role itself cannot be assigned as an ordinary institution membership.
create or replace function public.unimis_access_role_valid116(p_inst uuid,p_role uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.roles r where r.id=p_role and r.is_active and (r.institution_id is null or r.institution_id=p_inst)
 and r.code not in ('owner','superadmin','super_admin','platform_superadmin','deputy_access_authority','academic_panel','student','parent'))
$$;
do $$declare f record;begin
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in
 ('unimis_review_manager130','unimis_batch_access130','unimis_review_setup130','unimis_save_review_config130','unimis_create_committee130','unimis_assign_panel_member130','unimis_create_result_batch130','unimis_review_batches130','unimis_review_batch130','unimis_comment_review130','unimis_record_meeting130','unimis_confirm_meeting130','unimis_cancel_review130','unimis_publish_review130','unimis_my_panel_roles130') loop
 execute format('revoke all on function %s from public,anon',f.signature);
 execute format('grant execute on function %s to authenticated',f.signature);end loop;
end $$;
-- Restrictive policies also close inherited broad result-table access. Existing permissive
-- permissions are still required; these predicates never grant operational powers.
create or replace function public.unimis_student_self_scope130(p_student uuid,p_gpa boolean default false)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.students s where s.id=p_student and s.user_id=auth.uid())
 or exists(select 1 from public.guardian_student_links l join public.guardians g on g.id=l.guardian_id
 where l.student_id=p_student and l.status='active' and g.status='active' and g.user_id=auth.uid()
 and l.institution_id=g.institution_id and case when p_gpa then l.can_view_gpa else l.can_view_results end)
$$;
create or replace function public.unimis_result_scope130(p_inst uuid,p_student uuid,p_offering uuid,p_status text)
returns boolean language sql stable security definer set search_path='' as $$
 select public.unimis_review_manager130(p_inst)
 or exists(select 1 from public.unimis_effective_memberships116 m join public.roles r on r.id=m.role_id where m.user_id=auth.uid() and m.institution_id=p_inst and m.status='active' and r.is_active and r.code='auditor')
 or exists(select 1 from public.unimis_current_lecturer() me join public.course_lecturers cl on cl.lecturer_profile_id=me.lecturer_profile_id and cl.institution_id=me.institution_id where me.institution_id=p_inst and cl.course_offering_id=p_offering)
 or p_status='published' and public.unimis_student_self_scope130(p_student,false)
 or exists(select 1 from public.unimis_batch_results130 br join public.course_results cr on cr.id=br.result_id where cr.institution_id=p_inst and cr.student_id=p_student and cr.course_offering_id=p_offering and public.unimis_batch_access130(br.batch_id))
$$;
create or replace function public.unimis_period_result_scope130(p_inst uuid,p_student uuid,p_period uuid,p_status text)
returns boolean language sql stable security definer set search_path='' as $$
 select public.unimis_review_manager130(p_inst)
 or exists(select 1 from public.unimis_effective_memberships116 m join public.roles r on r.id=m.role_id where m.user_id=auth.uid() and m.institution_id=p_inst and m.status='active' and r.is_active and r.code='auditor')
 or p_status='published' and public.unimis_student_self_scope130(p_student,true)
 or exists(select 1 from public.student_course_registrations scr join public.student_period_registrations spr on spr.id=scr.period_registration_id and spr.institution_id=p_inst
 join public.unimis_current_lecturer() me on me.institution_id=p_inst join public.course_lecturers cl on cl.institution_id=p_inst and cl.lecturer_profile_id=me.lecturer_profile_id and cl.course_offering_id=scr.course_offering_id
 where scr.institution_id=p_inst and scr.student_id=p_student and spr.academic_period_id=p_period)
 or exists(select 1 from public.unimis_batch_results130 br join public.course_results cr on cr.id=br.result_id join public.unimis_result_batches130 b on b.id=br.batch_id where b.institution_id=p_inst and b.academic_period_id=p_period and cr.student_id=p_student and public.unimis_batch_access130(b.id))
$$;
revoke all on function public.unimis_student_self_scope130(uuid,boolean),public.unimis_result_scope130(uuid,uuid,uuid,text),public.unimis_period_result_scope130(uuid,uuid,uuid,text) from public,anon;
grant execute on function public.unimis_student_self_scope130(uuid,boolean),public.unimis_result_scope130(uuid,uuid,uuid,text),public.unimis_period_result_scope130(uuid,uuid,uuid,text) to authenticated;
drop policy if exists unimis_course_result_scope130 on public.course_results;
create policy unimis_course_result_scope130 on public.course_results as restrictive for all to authenticated
 using(public.unimis_result_scope130(institution_id,student_id,course_offering_id,result_status))
 with check(public.unimis_result_scope130(institution_id,student_id,course_offering_id,result_status));
drop policy if exists unimis_period_result_scope130 on public.student_period_results;
create policy unimis_period_result_scope130 on public.student_period_results as restrictive for all to authenticated
 using(public.unimis_period_result_scope130(institution_id,student_id,academic_period_id,status))
 with check(public.unimis_period_result_scope130(institution_id,student_id,academic_period_id,status));
drop policy if exists unimis_assessment_scope130 on public.assessment_scores;
create policy unimis_assessment_scope130 on public.assessment_scores as restrictive for all to authenticated
 using(exists(select 1 from public.student_course_registrations scr where scr.id=student_course_registration_id and public.unimis_result_scope130(scr.institution_id,scr.student_id,scr.course_offering_id,'assessment')))
 with check(exists(select 1 from public.student_course_registrations scr where scr.id=student_course_registration_id and public.unimis_result_scope130(scr.institution_id,scr.student_id,scr.course_offering_id,'assessment')));
drop policy if exists unimis_result_history_scope130 on public.result_approval_history;
create policy unimis_result_history_scope130 on public.result_approval_history as restrictive for all to authenticated
 using(exists(select 1 from public.course_results cr where cr.id=course_result_id and public.unimis_result_scope130(cr.institution_id,cr.student_id,cr.course_offering_id,cr.result_status)))
 with check(exists(select 1 from public.course_results cr where cr.id=course_result_id and public.unimis_result_scope130(cr.institution_id,cr.student_id,cr.course_offering_id,cr.result_status)));

-- Shared-course returns can be corrected without reopening another department's submitted or published rows.
create or replace function public.unimis_submit_course_results(p_course_offering_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_inst uuid;
  v_lp uuid;
  v_weight numeric;
  v_assess int;
  v_credit numeric;
  v_scheme uuid;
  r record;
  b record;
  n int:=0;
  old_status text;
begin
  select institution_id,lecturer_profile_id
    into v_inst,v_lp
  from public.unimis_current_lecturer();

  if not exists(
    select 1
    from public.course_lecturers
    where institution_id=v_inst
      and lecturer_profile_id=v_lp
      and course_offering_id=p_course_offering_id
  ) then
    raise exception 'You are not allocated to this course offering';
  end if;

  select c.credit_hours
    into v_credit
  from public.course_offerings co
  join public.courses c on c.id=co.course_id
  where co.id=p_course_offering_id
    and co.institution_id=v_inst;

  if v_credit is null then
    raise exception 'Course offering or course credit hours could not be resolved';
  end if;

  select coalesce(sum(weight_percent),0),count(*)
    into v_weight,v_assess
  from public.assessment_items
  where institution_id=v_inst
    and course_offering_id=p_course_offering_id
    and status<>'cancelled';

  if v_assess=0 or v_weight<>100 then
    raise exception
      'Assessment weights must total exactly 100%% before results can be submitted. Current total: %%%',
      v_weight;
  end if;

  for r in
    select
      s.id student_id,
      scr.id scr_id,
      coalesce(sum(sc.weighted_score),0)::numeric(7,2) total_score,
      count(ai.id) filter(where sc.id is null) missing_count
    from public.student_course_registrations scr
    join public.student_period_registrations spr
      on spr.id=scr.period_registration_id
    join public.students s
      on s.id=scr.student_id
    cross join public.assessment_items ai
    left join public.assessment_scores sc
      on sc.assessment_item_id=ai.id
     and sc.student_course_registration_id=scr.id
    where scr.institution_id=v_inst
      and scr.course_offering_id=p_course_offering_id
      and lower(coalesce(scr.status,'')) not in ('dropped','cancelled','withdrawn')
      and lower(coalesce(spr.registration_status,''))='approved'
      and ai.institution_id=v_inst
      and ai.course_offering_id=p_course_offering_id
      and ai.status<>'cancelled'
    group by s.id,scr.id
  loop
    select result_status into old_status from public.course_results where student_course_registration_id=r.scr_id and institution_id=v_inst;
    if old_status in ('submitted','approved','published') then continue;end if;
    if r.missing_count>0 then
      raise exception 'Cannot submit: at least one registered student has missing assessment marks';
    end if;

    -- 079 resolver: course -> student's programme -> institution default.
    v_scheme:=public.unimis_resolve_grading_scheme(
      p_course_offering_id,
      r.student_id
    );

    select *
      into b
    from public.grade_bands
    where institution_id=v_inst
      and grading_scheme_id=v_scheme
      and r.total_score>=min_score
      and r.total_score<=max_score
    order by min_score desc
    limit 1;

    if b.id is null then
      raise exception
        'No grade band in the resolved grading scheme covers score % for student %',
        r.total_score,r.student_id;
    end if;


    insert into public.course_results(
      institution_id,
      student_course_registration_id,
      student_id,
      course_offering_id,
      grading_scheme_id,
      total_score,
      letter_grade,
      grade_point,
      quality_points,
      result_status,
      passed,
      submitted_by,
      submitted_at
    )
    values(
      v_inst,
      r.scr_id,
      r.student_id,
      p_course_offering_id,
      v_scheme,
      r.total_score,
      b.letter_grade,
      b.grade_point,
      round(b.grade_point*coalesce(v_credit,0),2),
      'submitted',
      b.is_pass,
      auth.uid(),
      now()
    )
    on conflict(student_course_registration_id)
    do update set
      grading_scheme_id=excluded.grading_scheme_id,
      total_score=excluded.total_score,
      letter_grade=excluded.letter_grade,
      grade_point=excluded.grade_point,
      quality_points=excluded.quality_points,
      result_status='submitted',
      passed=excluded.passed,
      submitted_by=auth.uid(),
      submitted_at=now(),
      approved_by=null,
      approved_at=null,
      published_at=null,
      updated_at=now();

    insert into public.result_approval_history(
      institution_id,course_result_id,old_status,new_status,
      action_by,action_at,notes
    )
    select
      v_inst,id,coalesce(old_status,'draft'),'submitted',
      auth.uid(),now(),
      'Submitted by lecturer; grading scheme resolved automatically'
    from public.course_results
    where student_course_registration_id=r.scr_id;

    n:=n+1;
  end loop;

  return jsonb_build_object(
    'submitted',n,
    'grading_resolution','course_override -> student_programme -> institution_default'
  );
end $$;

create or replace function public.unimis_save_ca_exam_scores(p_course_offering_id uuid,p_records jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid;v_lp uuid;v_ca uuid;v_exam uuid;v_camax numeric;v_exammax numeric;r jsonb;v numeric;n int:=0;
begin
 select institution_id,lecturer_profile_id into v_inst,v_lp from public.unimis_current_lecturer();
 if not exists(select 1 from public.course_lecturers where institution_id=v_inst and lecturer_profile_id=v_lp and course_offering_id=p_course_offering_id)
 then raise exception 'You are not allocated to this course offering'; end if;

 select id,max_score into v_ca,v_camax from public.assessment_items where institution_id=v_inst and course_offering_id=p_course_offering_id and name='Continuous Assessment' and status<>'cancelled' limit 1;
 select id,max_score into v_exam,v_exammax from public.assessment_items where institution_id=v_inst and course_offering_id=p_course_offering_id and name='Final Examination' and status<>'cancelled' limit 1;
 if v_ca is null or v_exam is null then raise exception 'Configure CA + Exam mode first'; end if;

 for r in select * from jsonb_array_elements(coalesce(p_records,'[]'::jsonb)) loop
   if not exists(select 1 from public.student_course_registrations scr join public.student_period_registrations spr on spr.id=scr.period_registration_id and spr.institution_id=v_inst
   where scr.id=(r->>'course_registration_id')::uuid and scr.institution_id=v_inst and scr.student_id=(r->>'student_id')::uuid and scr.course_offering_id=p_course_offering_id and scr.status not in ('dropped','withdrawn') and spr.registration_status='approved') then raise exception 'Student is not on this allocated approved class list';end if;

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

create or replace function public.unimis_save_assessment_scores(p_assessment_item_id uuid,p_records jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid; v_lp uuid; v_off uuid; v_max numeric; v_weight numeric; r jsonb; v_raw numeric; n int:=0;
begin
 select institution_id,lecturer_profile_id into v_inst,v_lp from public.unimis_current_lecturer();
 select course_offering_id,max_score,weight_percent into v_off,v_max,v_weight from public.assessment_items where id=p_assessment_item_id and institution_id=v_inst;
 if v_off is null or not exists(select 1 from public.course_lecturers where institution_id=v_inst and lecturer_profile_id=v_lp and course_offering_id=v_off) then raise exception 'Assessment is not in one of your allocated courses'; end if;

 for r in select * from jsonb_array_elements(coalesce(p_records,'[]'::jsonb)) loop
   if not exists(select 1 from public.student_course_registrations scr join public.student_period_registrations spr on spr.id=scr.period_registration_id and spr.institution_id=v_inst
   where scr.id=(r->>'course_registration_id')::uuid and scr.institution_id=v_inst and scr.student_id=(r->>'student_id')::uuid and scr.course_offering_id=v_off and scr.status not in ('dropped','withdrawn') and spr.registration_status='approved') then raise exception 'Student is not on this allocated approved class list';end if;

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

create or replace function public.unimis_guard_assessment_lock130()
returns trigger language plpgsql security definer set search_path='' as $$
declare sid uuid;
begin
 if tg_op='UPDATE' and (new.student_course_registration_id is distinct from old.student_course_registration_id or new.student_id is distinct from old.student_id or new.institution_id is distinct from old.institution_id or new.assessment_item_id is distinct from old.assessment_item_id) then raise exception 'Assessment identity cannot be reassigned';end if;
 if tg_op='DELETE' then sid:=old.student_course_registration_id;else sid:=new.student_course_registration_id;end if;
 if exists(select 1 from public.course_results where student_course_registration_id=sid and result_status in ('submitted','approved','published')) then raise exception 'This student result is locked; the committee must return it before marks change';end if;
 if tg_op='DELETE' then return old;else return new;end if;
end $$;
drop trigger if exists unimis_assessment_lock130 on public.assessment_scores;
create trigger unimis_assessment_lock130 before insert or update or delete on public.assessment_scores for each row execute function public.unimis_guard_assessment_lock130();
