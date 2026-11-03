create or replace function public.unimis_progression_access()
returns uuid language sql stable security definer set search_path='' as $$
 select iu.institution_id from public.unimis_effective_memberships116 iu
 join public.roles r on r.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active'
 and lower(coalesce(r.code,r.name)) in ('owner','administrator','admin','registrar','superadmin','super_admin','exam_officer','exams_officer','examination_officer','examinations_officer')
 order by iu.is_primary desc limit 1
$$;

grant execute on function public.unimis_progression_access() to authenticated;
