-- Build 161: Student Portal branding + short showcase video support.
alter table unimis.public_website_settings
 add column if not exists student_portal_image_url text,
 add column if not exists student_portal_title text,
 add column if not exists student_portal_text text;

-- Website media bucket now accepts short MP4/WebM demonstrations (50 MB max).
update storage.buckets
set file_size_limit=52428800,
    allowed_mime_types=array['image/jpeg','image/png','image/webp','video/mp4','video/webm']
where id='unimis-website-media';

-- Replaces Build 160 save function so Student Portal branding persists in the same save.
create or replace function unimis.unimis_save_website_settings(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=unimis as $$
declare v_inst uuid; v_role text; v_row unimis.public_website_settings;
begin
 select institution_id,role_code into v_inst,v_role from unimis.unimis_website_access126();
 if v_inst is null or v_role not in ('admin','administrator','owner','registrar','communications_officer') then raise exception 'Not authorised'; end if;
 insert into unimis.public_website_settings(
  institution_id,display_name,short_name,tagline,hero_title,hero_text,hero_image_url,secondary_image_url,about_title,about_text,admissions_intro,address,phone,admissions_phone,email,website_url,primary_cta_label,is_published,staff_portal_image_url,staff_portal_title,staff_portal_text,student_portal_image_url,student_portal_title,student_portal_text,updated_by
 ) values(
  v_inst,coalesce(nullif(trim(p_payload->>'display_name'),''),'University'),nullif(trim(p_payload->>'short_name'),''),nullif(trim(p_payload->>'tagline'),''),nullif(trim(p_payload->>'hero_title'),''),nullif(trim(p_payload->>'hero_text'),''),nullif(trim(p_payload->>'hero_image_url'),''),nullif(trim(p_payload->>'secondary_image_url'),''),nullif(trim(p_payload->>'about_title'),''),nullif(trim(p_payload->>'about_text'),''),nullif(trim(p_payload->>'admissions_intro'),''),nullif(trim(p_payload->>'address'),''),nullif(trim(p_payload->>'phone'),''),nullif(trim(p_payload->>'admissions_phone'),''),nullif(trim(p_payload->>'email'),''),nullif(trim(p_payload->>'website_url'),''),coalesce(nullif(trim(p_payload->>'primary_cta_label'),''),'Apply Now'),coalesce((p_payload->>'is_published')::boolean,true),nullif(trim(p_payload->>'staff_portal_image_url'),''),nullif(trim(p_payload->>'staff_portal_title'),''),nullif(trim(p_payload->>'staff_portal_text'),''),nullif(trim(p_payload->>'student_portal_image_url'),''),nullif(trim(p_payload->>'student_portal_title'),''),nullif(trim(p_payload->>'student_portal_text'),''),auth.uid()
 ) on conflict(institution_id) do update set
  display_name=excluded.display_name,short_name=excluded.short_name,tagline=excluded.tagline,hero_title=excluded.hero_title,hero_text=excluded.hero_text,hero_image_url=excluded.hero_image_url,secondary_image_url=excluded.secondary_image_url,about_title=excluded.about_title,about_text=excluded.about_text,admissions_intro=excluded.admissions_intro,address=excluded.address,phone=excluded.phone,admissions_phone=excluded.admissions_phone,email=excluded.email,website_url=excluded.website_url,primary_cta_label=excluded.primary_cta_label,is_published=excluded.is_published,staff_portal_image_url=excluded.staff_portal_image_url,staff_portal_title=excluded.staff_portal_title,staff_portal_text=excluded.staff_portal_text,student_portal_image_url=excluded.student_portal_image_url,student_portal_title=excluded.student_portal_title,student_portal_text=excluded.student_portal_text,updated_at=now(),updated_by=auth.uid()
 returning * into v_row; return to_jsonb(v_row);
end $$;
grant execute on function unimis.unimis_save_website_settings(jsonb) to authenticated;
