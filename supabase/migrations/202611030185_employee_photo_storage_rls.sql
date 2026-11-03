-- Build 185: Employee photo Storage RLS
-- Only Owner, HR and Accounts/Finance roles may manage/view employee photos.
-- Object paths must remain: <institution_uuid>/<employee_uuid>/<filename>

create or replace function public.unimis_can_manage_employee_photos185(p_institution_id uuid)
returns boolean
language sql
stable
security definer
set search_path=public,auth,pg_temp
as $$
  select exists (
    select 1
    from public.institution_users iu
    join public.roles r on r.id = iu.role_id
    where iu.institution_id = p_institution_id
      and iu.user_id = auth.uid()
      and iu.status = 'active'
      and lower(r.code) in (
        'owner',
        'hr_officer',
        'hr_manager',
        'finance_officer',
        'accountant'
      )
  );
$$;

revoke all on function public.unimis_can_manage_employee_photos185(uuid) from public;
grant execute on function public.unimis_can_manage_employee_photos185(uuid) to authenticated;

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values (
  'employee-photos',
  'employee-photos',
  false,
  5242880,
  array['image/jpeg','image/png','image/webp']
)
on conflict (id) do update set
  public=false,
  file_size_limit=5242880,
  allowed_mime_types=array['image/jpeg','image/png','image/webp'];

drop policy if exists "unimis_employee_photos_select_185" on storage.objects;
drop policy if exists "unimis_employee_photos_insert_185" on storage.objects;
drop policy if exists "unimis_employee_photos_update_185" on storage.objects;
drop policy if exists "unimis_employee_photos_delete_185" on storage.objects;

create policy "unimis_employee_photos_select_185"
on storage.objects for select to authenticated
using (
  bucket_id='employee-photos'
  and split_part(name,'/',1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and public.unimis_can_manage_employee_photos185(split_part(name,'/',1)::uuid)
);

create policy "unimis_employee_photos_insert_185"
on storage.objects for insert to authenticated
with check (
  bucket_id='employee-photos'
  and split_part(name,'/',1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and public.unimis_can_manage_employee_photos185(split_part(name,'/',1)::uuid)
);

create policy "unimis_employee_photos_update_185"
on storage.objects for update to authenticated
using (
  bucket_id='employee-photos'
  and split_part(name,'/',1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and public.unimis_can_manage_employee_photos185(split_part(name,'/',1)::uuid)
)
with check (
  bucket_id='employee-photos'
  and split_part(name,'/',1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and public.unimis_can_manage_employee_photos185(split_part(name,'/',1)::uuid)
);

create policy "unimis_employee_photos_delete_185"
on storage.objects for delete to authenticated
using (
  bucket_id='employee-photos'
  and split_part(name,'/',1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and public.unimis_can_manage_employee_photos185(split_part(name,'/',1)::uuid)
);
