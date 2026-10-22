-- Shared academic support, not private clinical counselling notes.
create table if not exists public.unimis_support_threads138(
 id uuid primary key default gen_random_uuid(),institution_id uuid not null references public.institutions(id),student_id uuid not null references public.students(id),course_offering_id uuid not null references public.course_offerings(id),status text not null default 'open' check(status in('open','resolved')),created_at timestamptz not null default now(),unique(student_id,course_offering_id));
create table if not exists public.unimis_support_messages138(
 id uuid primary key default gen_random_uuid(),thread_id uuid not null references public.unimis_support_threads138(id),author_id uuid not null references auth.users(id),author_kind text not null check(author_kind in('student','lecturer')),message text not null,follow_up date,created_at timestamptz not null default now());
alter table public.unimis_support_threads138 enable row level security;
alter table public.unimis_support_messages138 enable row level security;
revoke all on public.unimis_support_threads138,public.unimis_support_messages138 from public,anon,authenticated;

create or replace function public.unimis_support_scope138(p_student uuid,p_offering uuid,p_lecturer boolean default false)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.student_course_registrations scr join public.students s on s.id=scr.student_id and s.institution_id=scr.institution_id
 where scr.student_id=p_student and scr.course_offering_id=p_offering and scr.status not in('dropped','withdrawn') and
 ((not p_lecturer and s.user_id=auth.uid() and exists(select 1 from public.unimis_effective_memberships116 m join public.roles r on r.id=m.role_id and r.is_active where m.user_id=auth.uid() and m.institution_id=s.institution_id and m.status='active' and r.code='student'))
 or p_lecturer and exists(select 1 from public.unimis_current_lecturer() me join public.course_lecturers cl on cl.institution_id=me.institution_id and cl.lecturer_profile_id=me.lecturer_profile_id where cl.course_offering_id=p_offering and cl.institution_id=s.institution_id)))
$$;

create or replace function public.unimis_support_workspace138(p_lecturer boolean default false,p_student uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare sid uuid;inst uuid;lp uuid;options jsonb;records jsonb;threads jsonb;attendance jsonb;
begin
 if p_lecturer then
 select me.institution_id,me.lecturer_profile_id into inst,lp from public.unimis_current_lecturer() me;
 if lp is null then raise exception 'Active lecturer access required';end if;sid:=p_student;
 else
 select s.id,s.institution_id into sid,inst from public.students s where s.user_id=auth.uid() and exists(select 1 from public.unimis_effective_memberships116 m join public.roles ro on ro.id=m.role_id and ro.is_active where m.user_id=auth.uid() and m.institution_id=s.institution_id and m.status='active' and ro.code='student') order by s.id limit 1;
 if sid is null then raise exception 'Active student access required';end if;
 end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.student_number,x.academic_year,x.semester,x.code),'[]'::jsonb) into options from (
 select distinct s.id student_id,s.student_number,concat_ws(' ',s.first_name,s.middle_name,s.last_name) student_name,o.id offering_id,c.code,c.name,ay.name academic_year,ap.name semester
 from public.student_course_registrations scr join public.students s on s.id=scr.student_id and s.institution_id=inst
 join public.course_offerings o on o.id=scr.course_offering_id and o.institution_id=inst join public.courses c on c.id=o.course_id and c.institution_id=inst
 join public.academic_periods ap on ap.id=o.academic_period_id and ap.institution_id=inst join public.academic_years ay on ay.id=ap.academic_year_id and ay.institution_id=inst
 where scr.institution_id=inst and (p_lecturer or sid is null or scr.student_id=sid) and public.unimis_support_scope138(scr.student_id,o.id,p_lecturer)) x;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.year_start,x.period_number,x.code),'[]'::jsonb) into records from (
 select cr.id,cr.student_id,c.id course_id,c.code,c.name,c.credit_hours,cr.total_score,cr.letter_grade,cr.grade_point,cr.quality_points,cr.passed,ay.name academic_year,ay.start_date year_start,ap.id period_id,ap.name semester,ap.period_number
 from public.course_results cr join public.course_offerings o on o.id=cr.course_offering_id and o.institution_id=inst join public.courses c on c.id=o.course_id and c.institution_id=inst
 join public.academic_periods ap on ap.id=o.academic_period_id and ap.institution_id=inst join public.academic_years ay on ay.id=ap.academic_year_id and ay.institution_id=inst
 where cr.institution_id=inst and cr.student_id=sid and cr.result_status='published' and public.unimis_support_scope138(sid,o.id,p_lecturer)) x;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into threads from (
 select t.*,c.code,concat_ws(' ',s.first_name,s.last_name) student_name,s.student_number,
 coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'author_kind',m.author_kind,'message',m.message,'follow_up',m.follow_up,'created_at',m.created_at) order by m.created_at,m.id) from public.unimis_support_messages138 m where m.thread_id=t.id),'[]'::jsonb) messages
 from public.unimis_support_threads138 t join public.students s on s.id=t.student_id and s.institution_id=inst join public.course_offerings o on o.id=t.course_offering_id and o.institution_id=inst join public.courses c on c.id=o.course_id and c.institution_id=inst
 where t.institution_id=inst and (sid is null or t.student_id=sid) and public.unimis_support_scope138(t.student_id,t.course_offering_id,p_lecturer)) x;
 select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into attendance from (
 select c.code,ay.name academic_year,ap.name semester,count(*) recorded,count(*) filter(where a.attendance_status in('present','late')) attended
 from public.student_attendance a join public.student_course_registrations scr on scr.id=a.student_course_registration_id and scr.institution_id=inst and scr.student_id=a.student_id
 join public.course_offerings o on o.id=scr.course_offering_id and o.institution_id=inst join public.courses c on c.id=o.course_id and c.institution_id=inst
 join public.academic_periods ap on ap.id=o.academic_period_id and ap.institution_id=inst join public.academic_years ay on ay.id=ap.academic_year_id and ay.institution_id=inst
 where a.institution_id=inst and a.student_id=sid and public.unimis_support_scope138(sid,o.id,p_lecturer)
 group by c.code,ay.name,ap.name) x;
 return jsonb_build_object('student_id',sid,'options',options,'results',records,'threads',threads,'attendance',attendance,'gpa',case when p_lecturer then '[]'::jsonb else coalesce((select jsonb_agg(jsonb_build_object('period_id',pr.academic_period_id,'gpa',pr.gpa,'cgpa',pr.cgpa)) from public.student_period_results pr where pr.student_id=sid and pr.institution_id=inst and pr.status='published'),'[]'::jsonb) end,'scope',case when p_lecturer then 'Published results and recorded attendance in your assigned course offerings only. This is not the student''s full GPA or academic history.' else 'Your published course results and recorded attendance. Unpublished results are excluded.' end);
end $$;

create or replace function public.unimis_support_post138(p_student uuid,p_offering uuid,p_message text,p_follow_up date default null,p_status text default null,p_lecturer boolean default false)
returns uuid language plpgsql security definer set search_path='' as $$
declare tid uuid;inst uuid;
begin
 if not public.unimis_support_scope138(p_student,p_offering,p_lecturer) then raise exception 'Academic support access denied';end if;
 -- A lecturer must explicitly operate in lecturer mode; student mode requires ownership.
 if not p_lecturer and not exists(select 1 from public.students where id=p_student and user_id=auth.uid()) then raise exception 'Student ownership required';end if;
 if length(trim(coalesce(p_message,'')))<5 or length(p_message)>4000 then raise exception 'Enter a message of 5 to 4000 characters';end if;
 if p_follow_up is not null and p_follow_up<current_date then raise exception 'Follow-up date cannot be in the past';end if;
 if p_status is not null and (not p_lecturer or p_status not in('open','resolved')) then raise exception 'Only the assigned lecturer can set open or resolved';end if;
 select institution_id into inst from public.students where id=p_student;
 insert into public.unimis_support_threads138(institution_id,student_id,course_offering_id)values(inst,p_student,p_offering) on conflict(student_id,course_offering_id) do update set status=coalesce(p_status,'open') returning id into tid;
 if p_status is not null then update public.unimis_support_threads138 set status=p_status where id=tid;end if;
 insert into public.unimis_support_messages138(thread_id,author_id,author_kind,message,follow_up)values(tid,auth.uid(),case when p_lecturer then 'lecturer' else 'student' end,trim(p_message),p_follow_up);
 return tid;
end $$;
revoke all on function public.unimis_support_scope138(uuid,uuid,boolean),public.unimis_support_workspace138(boolean,uuid),public.unimis_support_post138(uuid,uuid,text,date,text,boolean) from public,anon;
grant execute on function public.unimis_support_workspace138(boolean,uuid),public.unimis_support_post138(uuid,uuid,text,date,text,boolean) to authenticated;
