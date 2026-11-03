-- Build 191 - unify HR permissions with existing UniMIS multi-role access.
-- No second authority table. Effective permissions come from approved active institution roles.

create or replace function public.unimis_hr_has_role191(p_institution_id uuid,p_role_codes text[])
returns boolean
language sql stable security definer
set search_path=public,auth,pg_temp
as $$
 select exists(
   select 1
   from public.institution_users iu
   join public.roles r on r.id=iu.role_id
   where iu.institution_id=p_institution_id
     and iu.user_id=auth.uid()
     and iu.status='active'
     and lower(r.code)=any(p_role_codes)
 );
$$;

create or replace function public.unimis_hr_set_employee_photo191(
 p_institution_id uuid,p_employee_id uuid,p_photo_path text
) returns jsonb
language plpgsql security definer
set search_path=public,auth,storage,pg_temp
as $$
begin
 if not public.unimis_hr_has_role191(
   p_institution_id,
   array['owner','hr_manager','hr_officer']
 ) then
   raise exception 'HR write access required';
 end if;

 -- Enforce correct tenant/employee folder. Prevents a photo uploaded for one
 -- employee from being linked to another employee.
 if p_photo_path is null
    or split_part(p_photo_path,'/',1) <> p_institution_id::text
    or split_part(p_photo_path,'/',2) <> p_employee_id::text then
   raise exception 'Employee photo path does not match this employee';
 end if;

 if not exists(
   select 1 from storage.objects
   where bucket_id='employee-photos' and name=p_photo_path
 ) then
   raise exception 'Uploaded employee photo was not found in storage';
 end if;

 update public.hrc_hr_employees
 set photo_path=p_photo_path, updated_at=now()
 where id=p_employee_id and tenant_id=p_institution_id;

 if not found then raise exception 'Employee not found'; end if;
 return jsonb_build_object('ok',true,'photo_path',p_photo_path);
end $$;

create or replace function public.unimis_hr_decide_leave191(
 p_institution_id uuid,p_request_id uuid,p_decision text,p_notes text default null
) returns jsonb
language plpgsql security definer
set search_path=public,auth,pg_temp
as $$
declare
 r public.hrc_hr_leave_requests%rowtype;
begin
 if not public.unimis_hr_has_role191(
   p_institution_id,
   array['owner','hr_manager','hr_officer']
 ) then
   raise exception 'HR leave approval access required';
 end if;

 if p_decision not in ('approved','rejected') then
   raise exception 'Invalid leave decision';
 end if;

 if p_decision='rejected'
    and nullif(btrim(coalesce(p_notes,'')),'') is null then
   raise exception 'Rejection reason is required';
 end if;

 select * into r
 from public.hrc_hr_leave_requests
 where id=p_request_id and tenant_id=p_institution_id
 for update;

 if r.id is null then raise exception 'Leave request not found'; end if;
 if r.status not in ('submitted','pending') then
   raise exception 'Only submitted leave requests can be decided';
 end if;

 update public.hrc_hr_leave_requests
 set status=p_decision,
     decision_notes=nullif(btrim(coalesce(p_notes,'')),''),
     decided_by=auth.uid(),
     decided_at=now()
 where id=r.id;

 return jsonb_build_object('ok',true,'status',p_decision);
end $$;

revoke all on function public.unimis_hr_has_role191(uuid,text[]) from public;
revoke all on function public.unimis_hr_set_employee_photo191(uuid,uuid,text) from public;
revoke all on function public.unimis_hr_decide_leave191(uuid,uuid,text,text) from public;

grant execute on function public.unimis_hr_has_role191(uuid,text[]) to authenticated;
grant execute on function public.unimis_hr_set_employee_photo191(uuid,uuid,text) to authenticated;
grant execute on function public.unimis_hr_decide_leave191(uuid,uuid,text,text) to authenticated;
