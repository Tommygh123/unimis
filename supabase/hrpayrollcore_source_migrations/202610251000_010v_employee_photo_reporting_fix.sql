-- 010v: reliable employee photo linkage after Storage upload.
create or replace function public.hr_set_employee_photo_path(p_tenant uuid,p_employee uuid,p_photo_path text)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if not public.has_tenant_role(p_tenant,array['owner','administrator','hr_manager','hr_officer']) then raise exception 'HR write access required'; end if;
 if p_photo_path is null or p_photo_path='' or split_part(p_photo_path,'/',1)<>p_tenant::text then raise exception 'Invalid employee photo path'; end if;
 update public.hr_employees set photo_path=p_photo_path where id=p_employee and tenant_id=p_tenant;
 if not found then raise exception 'Employee not found'; end if;
 insert into public.audit_events(tenant_id,actor_id,module,action,record_type,record_id,details)
 values(p_tenant,auth.uid(),'hr','employee.photo.updated','hr_employee',p_employee,jsonb_build_object('photo_path',p_photo_path));
 return jsonb_build_object('ok',true,'photo_path',p_photo_path);
end $$;
grant execute on function public.hr_set_employee_photo_path(uuid,uuid,text) to authenticated;
