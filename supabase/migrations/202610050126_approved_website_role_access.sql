-- Approved additional website roles remain scoped to the primary school.
create or replace function public.unimis_website_access126()
returns table(institution_id uuid,role_code text)
language sql stable security definer set search_path='' as $$
 select e.institution_id,r.code
 from public.unimis_effective_memberships116 e join public.roles r on r.id=e.role_id
 where e.user_id=auth.uid() and e.status='active' and r.is_active
 and r.code in ('admin','owner','communications_officer')
 and e.institution_id=(select m.institution_id from public.institution_users m
 where m.user_id=auth.uid() and m.status='active' order by m.is_primary desc nulls last,m.id limit 1)
 order by e.is_primary desc nulls last,r.code limit 1
$$;
revoke all on function public.unimis_website_access126() from public,anon,authenticated;

create or replace function public.unimis_website_admin_bootstrap()
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_inst uuid; v_role text;
begin
 select institution_id,role_code into v_inst,v_role from public.unimis_website_access126();

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

create or replace function public.unimis_save_website_settings(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_inst uuid; v_role text; v_row public.public_website_settings;
begin
 select institution_id,role_code into v_inst,v_role from public.unimis_website_access126();
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

create or replace function public.unimis_save_website_announcement(p_id uuid,p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_inst uuid; v_role text; v_row public.public_website_announcements;
begin
 select institution_id,role_code into v_inst,v_role from public.unimis_website_access126();
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

create or replace function public.unimis_delete_website_announcement(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare v_inst uuid; v_role text;
begin
 select institution_id,role_code into v_inst,v_role from public.unimis_website_access126();
 if v_inst is null or v_role not in ('admin','owner','communications_officer') then raise exception 'Not authorised'; end if;
 delete from public.public_website_announcements where id=p_id and institution_id=v_inst;
 return found;
end $$;

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
 select institution_id,role_code into v_inst,v_role from public.unimis_website_access126();

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

create or replace function public.unimis_delete_showcase_item(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare v_inst uuid; v_role text;
begin
 select institution_id,role_code into v_inst,v_role from public.unimis_website_access126();
 if v_inst is null or v_role not in ('admin','owner','communications_officer') then raise exception 'Not authorised'; end if;
 delete from public.public_university_showcase_items where id=p_id and institution_id=v_inst;
 return found;
end $$;

create or replace function public.unimis_save_programme_publication(p_programme_id uuid,p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_inst uuid; v_role text; v_row public.public_programme_publication;
begin
 select institution_id,role_code into v_inst,v_role from public.unimis_website_access126();
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

create or replace function public.unimis_save_staff_portal_branding(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_inst uuid;
  v_role text;
  v_row public.public_website_settings;
begin
  select institution_id,role_code into v_inst,v_role from public.unimis_website_access126();

  if v_inst is null or v_role not in ('admin','owner','communications_officer') then
    raise exception 'Not authorised to manage University Portal branding';
  end if;

  update public.public_website_settings
  set staff_portal_image_url=nullif(trim(p_payload->>'staff_portal_image_url'),''),
      staff_portal_title=nullif(trim(p_payload->>'staff_portal_title'),''),
      staff_portal_text=nullif(trim(p_payload->>'staff_portal_text'),''),
      updated_at=now()
  where institution_id=v_inst
  returning * into v_row;

  if v_row.institution_id is null then
    raise exception 'Public website settings have not been initialized';
  end if;

  return to_jsonb(v_row);
end $$;
