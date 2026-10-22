-- Read-only portal bootstrap: caller identity comes from auth.uid(), never client metadata.
begin;
create or replace function public.unimis_my_portal_memberships118()
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',m.id,'institution_id',m.institution_id,'user_id',m.user_id,'role_id',m.role_id,
  'staff_number',m.staff_number,'student_number',m.student_number,'status',m.status,
  'is_primary',m.is_primary,'joined_at',m.joined_at,
  'role',jsonb_build_object('id',r.id,'name',r.name,'code',r.code,'description',r.description,'is_active',r.is_active)
 ) order by m.is_primary desc,m.joined_at,m.id),'[]'::jsonb)
 from public.institution_users m join public.roles r on r.id=m.role_id
 where m.user_id=auth.uid() and m.status='active' and r.is_active
 and (r.institution_id is null or r.institution_id=m.institution_id)
$$;
revoke all on function public.unimis_my_portal_memberships118() from public,anon;
grant execute on function public.unimis_my_portal_memberships118() to authenticated;
notify pgrst,'reload schema';
commit;
