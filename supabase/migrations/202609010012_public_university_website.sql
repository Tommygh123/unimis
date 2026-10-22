-- UniMIS public-facing university website / admissions publication
-- 2026-09-01

create table if not exists public.public_website_settings (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null unique references public.institutions(id) on delete cascade,
  display_name text not null,
  short_name text,
  tagline text,
  hero_title text,
  hero_text text,
  hero_image_url text,
  secondary_image_url text,
  about_title text,
  about_text text,
  admissions_intro text,
  address text,
  phone text,
  admissions_phone text,
  email text,
  website_url text,
  primary_cta_label text not null default 'Apply Now',
  is_published boolean not null default true,
  updated_at timestamptz not null default now(),
  updated_by uuid
);

create table if not exists public.public_website_announcements (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  title text not null,
  summary text,
  body text,
  link_url text,
  published_at timestamptz,
  expires_at timestamptz,
  is_published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  updated_by uuid
);

create index if not exists idx_public_website_announcements_inst_pub
  on public.public_website_announcements(institution_id,is_published,published_at desc);

alter table public.public_website_settings enable row level security;
alter table public.public_website_announcements enable row level security;
revoke all on public.public_website_settings from anon, authenticated;
revoke all on public.public_website_announcements from anon, authenticated;

-- Demo/current institution branding. React never hard-codes the university name.
-- A future institution gets/updates its own row through Website Management.
insert into public.public_website_settings(
  institution_id,display_name,short_name,tagline,hero_title,hero_text,
  hero_image_url,secondary_image_url,about_title,about_text,admissions_intro,
  address,phone,admissions_phone,email
)
select i.id,
       'AG Technical University',
       'AGTU',
       'Technology, Innovation and Professional Excellence',
       'Build the skills to shape tomorrow',
       'Discover career-focused programmes, practical learning and an admissions journey you can complete and track online.',
       'https://images.unsplash.com/photo-1562774053-701939374585?auto=format&fit=crop&w=1800&q=85',
       'https://images.unsplash.com/photo-1523050854058-8df90110c9f1?auto=format&fit=crop&w=1400&q=85',
       'A future-focused technical university',
       'We combine applied teaching, technology and industry-focused education to prepare graduates for professional practice and innovation.',
       'Applications are managed through the UniMIS admissions platform. Create an applicant account, complete your profile and qualifications, pay the applicable fee, submit and track your decision online.',
       'Kumasi, Ghana',
       '+233 00 000 0000',
       '+233 00 000 0000',
       'admissions@example.edu.gh'
from public.institutions i
where not exists(select 1 from public.public_website_settings)
limit 1
on conflict (institution_id) do nothing;

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
  select s.institution_id, to_jsonb(s) into v_inst,v_settings
  from public.public_website_settings s
  where s.is_published=true
  limit 1;

  if v_inst is null then
    select i.id into v_inst from public.institutions i limit 1;
  end if;
  if v_inst is null then return '{}'::jsonb; end if;

  select to_jsonb(i) into v_institution from public.institutions i where i.id=v_inst;

  select coalesce(jsonb_agg(to_jsonb(p) order by p.name),'[]'::jsonb)
  into v_programmes
  from public.programmes p
  where p.institution_id=v_inst and coalesce(p.status,'active')='active';

  select coalesce(jsonb_agg(to_jsonb(c) order by c.created_at desc),'[]'::jsonb)
  into v_cycles
  from public.admission_cycles c
  where c.institution_id=v_inst and c.status='open';

  select coalesce(jsonb_agg(to_jsonb(a) order by coalesce(a.published_at,a.created_at) desc),'[]'::jsonb)
  into v_announcements
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
  'programme_count',(select count(*) from public.programmes p where p.institution_id=v_inst and coalesce(p.status,'active')='active'),
  'open_cycle_count',(select count(*) from public.admission_cycles c where c.institution_id=v_inst and c.status='open')
 );
end $$;
grant execute on function public.unimis_website_admin_bootstrap() to authenticated;

create or replace function public.unimis_save_website_settings(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_inst uuid; v_role text; v_row public.public_website_settings;
begin
 select iu.institution_id,r.code into v_inst,v_role
 from public.institution_users iu join public.roles r on r.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active'
 order by iu.is_primary desc nulls last limit 1;
 if v_inst is null or v_role not in ('admin','owner','communications_officer') then raise exception 'Not authorised'; end if;
 insert into public.public_website_settings(
   institution_id,display_name,short_name,tagline,hero_title,hero_text,hero_image_url,secondary_image_url,
   about_title,about_text,admissions_intro,address,phone,admissions_phone,email,website_url,primary_cta_label,is_published,updated_by
 ) values(
   v_inst,coalesce(nullif(trim(p_payload->>'display_name'),''),'University'),nullif(trim(p_payload->>'short_name'),''),
   nullif(trim(p_payload->>'tagline'),''),nullif(trim(p_payload->>'hero_title'),''),nullif(trim(p_payload->>'hero_text'),''),
   nullif(trim(p_payload->>'hero_image_url'),''),nullif(trim(p_payload->>'secondary_image_url'),''),
   nullif(trim(p_payload->>'about_title'),''),nullif(trim(p_payload->>'about_text'),''),nullif(trim(p_payload->>'admissions_intro'),''),
   nullif(trim(p_payload->>'address'),''),nullif(trim(p_payload->>'phone'),''),nullif(trim(p_payload->>'admissions_phone'),''),
   nullif(trim(p_payload->>'email'),''),nullif(trim(p_payload->>'website_url'),''),coalesce(nullif(trim(p_payload->>'primary_cta_label'),''),'Apply Now'),
   coalesce((p_payload->>'is_published')::boolean,true),auth.uid()
 ) on conflict(institution_id) do update set
   display_name=excluded.display_name,short_name=excluded.short_name,tagline=excluded.tagline,
   hero_title=excluded.hero_title,hero_text=excluded.hero_text,hero_image_url=excluded.hero_image_url,secondary_image_url=excluded.secondary_image_url,
   about_title=excluded.about_title,about_text=excluded.about_text,admissions_intro=excluded.admissions_intro,address=excluded.address,
   phone=excluded.phone,admissions_phone=excluded.admissions_phone,email=excluded.email,website_url=excluded.website_url,
   primary_cta_label=excluded.primary_cta_label,is_published=excluded.is_published,updated_at=now(),updated_by=auth.uid()
 returning * into v_row;
 return to_jsonb(v_row);
end $$;
grant execute on function public.unimis_save_website_settings(jsonb) to authenticated;

create or replace function public.unimis_save_website_announcement(p_id uuid,p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_inst uuid; v_role text; v_row public.public_website_announcements;
begin
 select iu.institution_id,r.code into v_inst,v_role
 from public.institution_users iu join public.roles r on r.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active'
 order by iu.is_primary desc nulls last limit 1;
 if v_inst is null or v_role not in ('admin','owner','communications_officer') then raise exception 'Not authorised'; end if;
 if p_id is null then
  insert into public.public_website_announcements(institution_id,title,summary,body,link_url,published_at,expires_at,is_published,created_by,updated_by)
  values(v_inst,p_payload->>'title',nullif(p_payload->>'summary',''),nullif(p_payload->>'body',''),nullif(p_payload->>'link_url',''),
         nullif(p_payload->>'published_at','')::timestamptz,nullif(p_payload->>'expires_at','')::timestamptz,coalesce((p_payload->>'is_published')::boolean,false),auth.uid(),auth.uid())
  returning * into v_row;
 else
  update public.public_website_announcements set title=p_payload->>'title',summary=nullif(p_payload->>'summary',''),body=nullif(p_payload->>'body',''),
   link_url=nullif(p_payload->>'link_url',''),published_at=nullif(p_payload->>'published_at','')::timestamptz,expires_at=nullif(p_payload->>'expires_at','')::timestamptz,
   is_published=coalesce((p_payload->>'is_published')::boolean,false),updated_at=now(),updated_by=auth.uid()
  where id=p_id and institution_id=v_inst returning * into v_row;
 end if;
 if v_row.id is null then raise exception 'Announcement not found'; end if;
 return to_jsonb(v_row);
end $$;
grant execute on function public.unimis_save_website_announcement(uuid,jsonb) to authenticated;

create or replace function public.unimis_delete_website_announcement(p_id uuid)
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
 delete from public.public_website_announcements where id=p_id and institution_id=v_inst;
 return found;
end $$;
grant execute on function public.unimis_delete_website_announcement(uuid) to authenticated;
