-- Build 159: tenant-scoped public website image uploads.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('unimis-website-media','unimis-website-media',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=true,file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png','image/webp'];

create or replace function public.unimis_can_manage_website_media159(p_institution_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(
   select 1 from public.unimis_website_access126() a
   where a.institution_id=p_institution_id
     and a.role_code in ('admin','owner','registrar','communications_officer')
 )
$$;
grant execute on function public.unimis_can_manage_website_media159(uuid) to authenticated;

drop policy if exists "unimis website media upload 159" on storage.objects;
create policy "unimis website media upload 159" on storage.objects for insert to authenticated
with check(bucket_id='unimis-website-media' and public.unimis_can_manage_website_media159(((storage.foldername(name))[1])::uuid));

drop policy if exists "unimis website media update 159" on storage.objects;
create policy "unimis website media update 159" on storage.objects for update to authenticated
using(bucket_id='unimis-website-media' and public.unimis_can_manage_website_media159(((storage.foldername(name))[1])::uuid))
with check(bucket_id='unimis-website-media' and public.unimis_can_manage_website_media159(((storage.foldername(name))[1])::uuid));

drop policy if exists "unimis website media delete 159" on storage.objects;
create policy "unimis website media delete 159" on storage.objects for delete to authenticated
using(bucket_id='unimis-website-media' and public.unimis_can_manage_website_media159(((storage.foldername(name))[1])::uuid));
