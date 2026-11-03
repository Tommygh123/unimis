
-- UniMIS: Humanities seed data + public programme grouping/publication controls
-- 2026-09-02
-- Safe/idempotent seed for the current institution.

create table if not exists public.public_programme_publication (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  programme_id uuid not null unique references public.programmes(id) on delete cascade,
  is_visible boolean not null default true,
  is_accepting_applications boolean not null default true,
  availability_label text,
  public_summary text,
  display_order integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_public_programme_publication_inst
  on public.public_programme_publication(institution_id,is_visible,display_order);

alter table public.public_programme_publication enable row level security;
revoke all on public.public_programme_publication from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 1. Faculty
-- ---------------------------------------------------------------------------
insert into public.faculties(institution_id,name,code,description,status)
select i.id,
       'Faculty of Humanities and Social Sciences',
       'FHSS',
       'Interdisciplinary education in communication, languages, social sciences, development, tourism and related professional fields.',
       'active'
from public.institutions i
where not exists (
  select 1 from public.faculties f
  where f.institution_id=i.id and upper(f.code)='FHSS'
)
order by i.created_at nulls last
limit 1;

-- ---------------------------------------------------------------------------
-- 2. Departments
-- ---------------------------------------------------------------------------
with inst as (
  select i.id institution_id from public.institutions i order by i.created_at nulls last limit 1
), fac as (
  select f.id faculty_id,f.institution_id
  from public.faculties f join inst i on i.institution_id=f.institution_id
  where upper(f.code)='FHSS' limit 1
), seed(name,code,description) as (
  values
    ('Department of Communication and Media Studies','CMS','Communication, journalism, digital media and professional media practice.'),
    ('Department of Languages and Liberal Studies','LLS','Applied language, communication, writing and liberal studies.'),
    ('Department of Social Sciences and Development Studies','SDS','Development, economics, sociology, public policy and social research.'),
    ('Department of Hospitality, Tourism and Events','HTE','Hospitality, tourism, destination management and events education.')
)
insert into public.departments(institution_id,faculty_id,name,code,description,status)
select f.institution_id,f.faculty_id,s.name,s.code,s.description,'active'
from fac f cross join seed s
where not exists (
  select 1 from public.departments d
  where d.institution_id=f.institution_id and upper(d.code)=upper(s.code)
);

-- ---------------------------------------------------------------------------
-- 3. Programmes planned for the next admissions cycle
-- ---------------------------------------------------------------------------
with inst as (
  select i.id institution_id from public.institutions i order by i.created_at nulls last limit 1
), seed(dept_code,name,code,award,duration,description,sort_order) as (
  values
    ('CMS','BA Communication Studies','BA-COMM','BA',4::numeric,'Professional communication, public relations, corporate communication and media practice.',10),
    ('CMS','BA Journalism and Digital Media','BA-JDM','BA',4::numeric,'Journalism, digital storytelling, multimedia production and contemporary newsroom practice.',20),
    ('LLS','BA Applied English and Communication','BA-AEC','BA',4::numeric,'Applied English, professional writing, communication and language studies.',30),
    ('LLS','BA French and Applied Communication','BA-FAC','BA',4::numeric,'French language proficiency combined with applied communication for professional and international contexts.',40),
    ('SDS','BSc Development Studies','BSC-DEV','BSc',4::numeric,'Development planning, community development, policy, research and project practice.',50),
    ('SDS','BSc Economics','BSC-ECON','BSc',4::numeric,'Economic analysis, quantitative reasoning, policy and applied economics.',60),
    ('SDS','BA Sociology and Social Policy','BA-SSP','BA',4::numeric,'Sociology, social policy, institutions, communities and evidence-based social intervention.',70),
    ('HTE','BSc Hospitality Management','BSC-HM','BSc',4::numeric,'Hospitality operations, service management, entrepreneurship and industry practice.',80),
    ('HTE','BSc Tourism Management','BSC-TM','BSc',4::numeric,'Tourism planning, destination management, sustainable tourism and visitor experience.',90),
    ('HTE','BSc Event Management','BSC-EM','BSc',4::numeric,'Professional event planning, production, marketing, logistics and experience management.',100)
)
insert into public.programmes(institution_id,department_id,name,code,award_type,duration_years,description,status)
select i.institution_id,d.id,s.name,s.code,s.award,s.duration,s.description,'active'
from inst i
join seed s on true
join public.departments d
  on d.institution_id=i.institution_id and upper(d.code)=upper(s.dept_code)
where not exists (
  select 1 from public.programmes p
  where p.institution_id=i.institution_id and upper(p.code)=upper(s.code)
);

-- Mark the new programmes as visible on the website but NOT selectable yet.
with inst as (
  select i.id institution_id from public.institutions i order by i.created_at nulls last limit 1
), seed(code,summary,sort_order) as (
  values
    ('BA-COMM','Communication, public relations and professional media practice.',10),
    ('BA-JDM','Journalism and digital-first multimedia storytelling.',20),
    ('BA-AEC','Applied English, writing and professional communication.',30),
    ('BA-FAC','French language and applied communication for international contexts.',40),
    ('BSC-DEV','Development planning, policy and community-focused practice.',50),
    ('BSC-ECON','Applied economics, policy and quantitative analysis.',60),
    ('BA-SSP','Sociology, social policy and evidence-based social intervention.',70),
    ('BSC-HM','Hospitality operations, service management and entrepreneurship.',80),
    ('BSC-TM','Tourism, destinations and sustainable visitor experiences.',90),
    ('BSC-EM','Professional event planning, production and marketing.',100)
)
insert into public.public_programme_publication(
  institution_id,programme_id,is_visible,is_accepting_applications,
  availability_label,public_summary,display_order
)
select i.institution_id,p.id,true,false,'Coming next admission cycle',s.summary,s.sort_order
from inst i
join seed s on true
join public.programmes p on p.institution_id=i.institution_id and upper(p.code)=upper(s.code)
on conflict(programme_id) do update set
  is_visible=excluded.is_visible,
  is_accepting_applications=excluded.is_accepting_applications,
  availability_label=excluded.availability_label,
  public_summary=excluded.public_summary,
  display_order=excluded.display_order,
  updated_at=now();

-- Existing programmes without a publication row remain visible/current by default.

-- ---------------------------------------------------------------------------
-- 4. Public website bootstrap: include Faculty + Department + publication info
-- ---------------------------------------------------------------------------
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
    ),
    '[]'::jsonb
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

  return jsonb_build_object(
    'institution',coalesce(v_institution,'{}'::jsonb),
    'settings',coalesce(v_settings,'{}'::jsonb),
    'programmes',v_programmes,
    'cycles',v_cycles,
    'announcements',v_announcements
  );
end $$;

grant execute on function public.unimis_public_website_bootstrap() to anon, authenticated;
