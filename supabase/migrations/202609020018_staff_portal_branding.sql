alter table public.public_website_settings
  add column if not exists staff_portal_image_url text,
  add column if not exists staff_portal_title text,
  add column if not exists staff_portal_text text;

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
  select iu.institution_id,r.code into v_inst,v_role
  from public.institution_users iu
  join public.roles r on r.id=iu.role_id
  where iu.user_id=auth.uid() and iu.status='active'
  order by iu.is_primary desc nulls last limit 1;

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

grant execute on function public.unimis_save_staff_portal_branding(jsonb) to authenticated;
