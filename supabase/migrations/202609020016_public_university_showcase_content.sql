-- UniMIS Public University Website: research, alumni, labs/workshops,
-- student projects, campus activities and other continuously updated public content.
-- News/blog functionality is intentionally not duplicated here.

create table if not exists public.public_university_showcase_items (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  content_type text not null,
  title text not null,
  summary text,
  body text,
  image_url text,
  link_url text,
  event_date date,
  person_name text,
  person_role text,
  programme_name text,
  project_year integer,
  tags text[] not null default '{}',
  extra jsonb not null default '{}',
  is_featured boolean not null default false,
  is_published boolean not null default false,
  display_order integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  updated_by uuid,
  constraint public_university_showcase_type_chk check (
    content_type in (
      'research','lab_workshop','student_project','alumni',
      'campus_life','achievement','partnership','community'
    )
  )
);

create index if not exists idx_public_showcase_inst_type_pub
  on public.public_university_showcase_items(institution_id,content_type,is_published,display_order);

alter table public.public_university_showcase_items enable row level security;
revoke all on public.public_university_showcase_items from anon, authenticated;

-- Draft starter content: visible to administrators for editing, but not public until published.
with inst as (
  select i.id institution_id
  from public.institutions i
  order by i.created_at nulls last
  limit 1
), seed(content_type,title,summary,body,programme_name,display_order) as (
  values
    ('research','Applied Research and Innovation','Feature current faculty and student research, grants, publications and industry collaborations here.','Replace this draft with an approved research story, project outcome, research centre update or publication highlight.',null,10),
    ('lab_workshop','Learning in the Laboratory and Workshop','Show practical sessions, laboratory exercises, technical workshops and field-based learning.','Replace this draft with a real laboratory or workshop activity. Add an image, date and programme where applicable.',null,20),
    ('student_project','Student Project Showcase','Compile final-year projects, prototypes, design projects, software systems and community solutions.','Replace this draft with a completed student project. The project list can grow continuously and be filtered by year or programme.',null,30),
    ('alumni','Alumni Impact and Activities','Share alumni achievements, reunions, mentoring, career stories and contributions to the university.','Replace this draft with an approved alumni activity or profile.',null,40),
    ('campus_life','Student Life and Campus Activities','Publish clubs, competitions, exhibitions, field trips, seminars and student-development activities.','Replace this draft with a current student-life story.',null,50),
    ('partnership','Industry and Community Partnerships','Highlight collaborations with industry, professional bodies, communities and other institutions.','Replace this draft with an approved partnership or engagement story.',null,60)
)
insert into public.public_university_showcase_items(
  institution_id,content_type,title,summary,body,programme_name,display_order,is_published
)
select i.institution_id,s.content_type,s.title,s.summary,s.body,s.programme_name,s.display_order,false
from inst i cross join seed s
where not exists (
  select 1 from public.public_university_showcase_items x
  where x.institution_id=i.institution_id and x.content_type=s.content_type and x.title=s.title
);

-- Public bootstrap: preserve grouped programmes from migration 015 and add showcase items.
create or replace function public.unimis_public_website_bootstrap()
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_inst uuid;
  v_settings jsonb;
  v_institution jsonb;
  v_programmes jsonb;
  v_cycles jsonb;
  v_announcements jsonb;
  v_showcase jsonb;
  v_counts jsonb;
begin
  select s.institution_id, to_jsonb(s)
    into v_inst,v_settings
  from public.public_website_settings s
  where s.is_published=true
  limit 1;

  if v_inst is null then
    select i.id into v_inst from public.institutions i order by i.created_at nulls last limit 1;
  end if;
  if v_inst is null then return '{}'::jsonb; end if;

  select to_jsonb(i) into v_institution
  from public.institutions i where i.id=v_inst;

  select coalesce(
    jsonb_agg(
      to_jsonb(p)
      || jsonb_build_object(
        'department_name',d.name,
        'department_code',d.code,
        'faculty_id',f.id,
        'faculty_name',f.name,
        'faculty_code',f.code,
        'is_accepting_applications',coalesce(pp.is_accepting_applications,true),
        'availability_label',coalesce(pp.availability_label,'Applications open'),
        'public_summary',coalesce(pp.public_summary,p.description),
        'display_order',coalesce(pp.display_order,100)
      )
      order by f.name,d.name,coalesce(pp.display_order,100),p.name
    ), '[]'::jsonb
  ) into v_programmes
  from public.programmes p
  left join public.departments d on d.id=p.department_id
  left join public.faculties f on f.id=d.faculty_id
  left join public.public_programme_publication pp on pp.programme_id=p.id
  where p.institution_id=v_inst
    and coalesce(p.status,'active')='active'
    and coalesce(pp.is_visible,true)=true;

  select coalesce(jsonb_agg(to_jsonb(c) order by c.created_at desc),'[]'::jsonb)
    into v_cycles
  from public.admission_cycles c
  where c.institution_id=v_inst and c.status='open';

  select coalesce(
    jsonb_agg(to_jsonb(a) order by coalesce(a.published_at,a.created_at) desc),
    '[]'::jsonb
  ) into v_announcements
  from public.public_website_announcements a
  where a.institution_id=v_inst
    and a.is_published=true
    and (a.published_at is null or a.published_at<=now())
    and (a.expires_at is null or a.expires_at>now());

  select coalesce(
    jsonb_agg(to_jsonb(x) order by x.content_type,x.is_featured desc,x.display_order,coalesce(x.event_date,current_date) desc,x.created_at desc),
    '[]'::jsonb
  ) into v_showcase
  from public.public_university_showcase_items x
  where x.institution_id=v_inst and x.is_published=true;

  select jsonb_build_object(
    'faculties',(select count(*) from public.faculties f where f.institution_id=v_inst and f.status='active'),
    'departments',(select count(*) from public.departments d where d.institution_id=v_inst and d.status='active'),
    'programmes',(select count(*) from public.programmes p where p.institution_id=v_inst and p.status='active')
  ) into v_counts;

  return jsonb_build_object(
    'institution',coalesce(v_institution,'{}'::jsonb),
    'settings',coalesce(v_settings,'{}'::jsonb),
    'programmes',v_programmes,
    'cycles',v_cycles,
    'announcements',v_announcements,
    'showcase_items',v_showcase,
    'academic_counts',v_counts
  );
end $$;

grant execute on function public.unimis_public_website_bootstrap() to anon, authenticated;

-- Admin bootstrap now also supplies all showcase items and programme publication controls.
create or replace function public.unimis_website_admin_bootstrap()
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_inst uuid; v_role text;
begin
 select iu.institution_id,r.code into v_inst,v_role
 from public.institution_users iu join public.roles r on r.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active'
 order by iu.is_primary desc nulls last limit 1;

 if v_inst is null or v_role not in ('admin','owner','communications_officer') then
   raise exception 'Not authorised to manage the public website';
 end if;

 return jsonb_build_object(
  'settings',(select to_jsonb(s) from public.public_website_settings s where s.institution_id=v_inst),
  'institution',(select to_jsonb(i) from public.institutions i where i.id=v_inst),
  'announcements',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc) from public.public_website_announcements a where a.institution_id=v_inst),'[]'::jsonb),
  'showcase_items',coalesce((select jsonb_agg(to_jsonb(x) order by x.content_type,x.display_order,x.created_at desc) from public.public_university_showcase_items x where x.institution_id=v_inst),'[]'::jsonb),
  'programme_publication',coalesce((
    select jsonb_agg(
      to_jsonb(pp)||jsonb_build_object('programme_name',p.name,'programme_code',p.code,'department_name',d.name,'faculty_name',f.name)
      order by f.name,d.name,pp.display_order,p.name
    )
    from public.public_programme_publication pp
    join public.programmes p on p.id=pp.programme_id
    left join public.departments d on d.id=p.department_id
    left join public.faculties f on f.id=d.faculty_id
    where pp.institution_id=v_inst
  ),'[]'::jsonb),
  'programme_count',(select count(*) from public.programmes p where p.institution_id=v_inst and coalesce(p.status,'active')='active'),
  'open_cycle_count',(select count(*) from public.admission_cycles c where c.institution_id=v_inst and c.status='open')
 );
end $$;

grant execute on function public.unimis_website_admin_bootstrap() to authenticated;

create or replace function public.unimis_save_showcase_item(p_id uuid,p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_inst uuid;
  v_role text;
  v_row public.public_university_showcase_items;
  v_type text:=lower(coalesce(p_payload->>'content_type',''));
begin
 select iu.institution_id,r.code into v_inst,v_role
 from public.institution_users iu join public.roles r on r.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active'
 order by iu.is_primary desc nulls last limit 1;

 if v_inst is null or v_role not in ('admin','owner','communications_officer') then
   raise exception 'Not authorised';
 end if;

 if v_type not in ('research','lab_workshop','student_project','alumni','campus_life','achievement','partnership','community') then
   raise exception 'Unsupported content type';
 end if;

 if p_id is null then
  insert into public.public_university_showcase_items(
   institution_id,content_type,title,summary,body,image_url,link_url,event_date,
   person_name,person_role,programme_name,project_year,tags,extra,is_featured,
   is_published,display_order,created_by,updated_by
  ) values(
   v_inst,v_type,trim(p_payload->>'title'),nullif(trim(p_payload->>'summary'),''),nullif(trim(p_payload->>'body'),''),
   nullif(trim(p_payload->>'image_url'),''),nullif(trim(p_payload->>'link_url'),''),nullif(p_payload->>'event_date','')::date,
   nullif(trim(p_payload->>'person_name'),''),nullif(trim(p_payload->>'person_role'),''),nullif(trim(p_payload->>'programme_name'),''),
   nullif(p_payload->>'project_year','')::integer,
   coalesce(array(select jsonb_array_elements_text(coalesce(p_payload->'tags','[]'::jsonb))),'{}'::text[]),
   coalesce(p_payload->'extra','{}'::jsonb),
   coalesce((p_payload->>'is_featured')::boolean,false),coalesce((p_payload->>'is_published')::boolean,false),
   coalesce(nullif(p_payload->>'display_order','')::integer,100),auth.uid(),auth.uid()
  ) returning * into v_row;
 else
  update public.public_university_showcase_items set
   content_type=v_type,title=trim(p_payload->>'title'),summary=nullif(trim(p_payload->>'summary'),''),body=nullif(trim(p_payload->>'body'),''),
   image_url=nullif(trim(p_payload->>'image_url'),''),link_url=nullif(trim(p_payload->>'link_url'),''),event_date=nullif(p_payload->>'event_date','')::date,
   person_name=nullif(trim(p_payload->>'person_name'),''),person_role=nullif(trim(p_payload->>'person_role'),''),programme_name=nullif(trim(p_payload->>'programme_name'),''),
   project_year=nullif(p_payload->>'project_year','')::integer,
   tags=coalesce(array(select jsonb_array_elements_text(coalesce(p_payload->'tags','[]'::jsonb))),'{}'::text[]),
   extra=coalesce(p_payload->'extra','{}'::jsonb),is_featured=coalesce((p_payload->>'is_featured')::boolean,false),
   is_published=coalesce((p_payload->>'is_published')::boolean,false),display_order=coalesce(nullif(p_payload->>'display_order','')::integer,100),
   updated_at=now(),updated_by=auth.uid()
  where id=p_id and institution_id=v_inst
  returning * into v_row;
 end if;

 if v_row.id is null then raise exception 'Website content item not found'; end if;
 return to_jsonb(v_row);
end $$;

grant execute on function public.unimis_save_showcase_item(uuid,jsonb) to authenticated;

create or replace function public.unimis_delete_showcase_item(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare v_inst uuid; v_role text;
begin
 select iu.institution_id,r.code into v_inst,v_role
 from public.institution_users iu join public.roles r on r.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active'
 order by iu.is_primary desc nulls last limit 1;
 if v_inst is null or v_role not in ('admin','owner','communications_officer') then raise exception 'Not authorised'; end if;
 delete from public.public_university_showcase_items where id=p_id and institution_id=v_inst;
 return found;
end $$;

grant execute on function public.unimis_delete_showcase_item(uuid) to authenticated;

create or replace function public.unimis_save_programme_publication(p_programme_id uuid,p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_inst uuid; v_role text; v_row public.public_programme_publication;
begin
 select iu.institution_id,r.code into v_inst,v_role
 from public.institution_users iu join public.roles r on r.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active'
 order by iu.is_primary desc nulls last limit 1;
 if v_inst is null or v_role not in ('admin','owner','communications_officer') then raise exception 'Not authorised'; end if;
 if not exists(select 1 from public.programmes p where p.id=p_programme_id and p.institution_id=v_inst) then raise exception 'Programme not found'; end if;

 insert into public.public_programme_publication(
   institution_id,programme_id,is_visible,is_accepting_applications,availability_label,public_summary,display_order
 ) values(
   v_inst,p_programme_id,coalesce((p_payload->>'is_visible')::boolean,true),coalesce((p_payload->>'is_accepting_applications')::boolean,true),
   nullif(trim(p_payload->>'availability_label'),''),nullif(trim(p_payload->>'public_summary'),''),coalesce(nullif(p_payload->>'display_order','')::integer,100)
 )
 on conflict(programme_id) do update set
   is_visible=excluded.is_visible,is_accepting_applications=excluded.is_accepting_applications,
   availability_label=excluded.availability_label,public_summary=excluded.public_summary,
   display_order=excluded.display_order,updated_at=now()
 returning * into v_row;
 return to_jsonb(v_row);
end $$;

grant execute on function public.unimis_save_programme_publication(uuid,jsonb) to authenticated;
