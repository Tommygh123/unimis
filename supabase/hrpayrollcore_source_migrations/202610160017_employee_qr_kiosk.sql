-- 005d Employee QR Scanner & Site Kiosk
alter table public.hr_employees add column if not exists auth_user_id uuid references auth.users(id) on delete set null;
create unique index if not exists uq_hr_employee_auth_user on public.hr_employees(auth_user_id) where auth_user_id is not null;

create or replace function public.hr_my_employee(p_tenant uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare e public.hr_employees%rowtype; mail text;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select * into e from public.hr_employees where tenant_id=p_tenant and auth_user_id=auth.uid() and employment_status='active' limit 1;
 if e.id is null then
   mail=lower(coalesce(auth.jwt()->>'email',''));
   if mail<>'' then
     select * into e from public.hr_employees where tenant_id=p_tenant and lower(coalesce(email,''))=mail and employment_status='active' limit 1;
     if e.id is not null and e.auth_user_id is null then update public.hr_employees set auth_user_id=auth.uid() where id=e.id; end if;
   end if;
 end if;
 if e.id is null then return null; end if;
 return jsonb_build_object('id',e.id,'employee_no',e.employee_no,'first_name',e.first_name,'last_name',e.last_name,'email',e.email);
end $$;
grant execute on function public.hr_my_employee(uuid) to authenticated;
