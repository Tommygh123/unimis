-- Build 198 production migration (normal dedicated UniMIS project / public schema)
create or replace function public.hr_auto_employee_no()
returns trigger language plpgsql security definer set search_path=public as $$
declare k uuid:=coalesce(new.tenant_id,'00000000-0000-0000-0000-000000000000'::uuid); n bigint;
begin
 if new.employee_no is null or btrim(new.employee_no)='' then
  perform pg_advisory_xact_lock(hashtext(k::text||':hrc_hr_employees'));
  select coalesce(max((regexp_match(employee_no,'^EMP-([0-9]+)$'))[1]::bigint),0) into n
  from public.hrc_hr_employees where tenant_id=k and employee_no ~ '^EMP-[0-9]+$';
  new.employee_no:='EMP-'||lpad((n+1)::text,4,'0');
 end if;
 return new;
end $$;
drop trigger if exists trg_auto_employee_no on public.hrc_hr_employees;
create trigger trg_auto_employee_no before insert on public.hrc_hr_employees for each row execute function public.hr_auto_employee_no();
create unique index if not exists uq_hrc_employee_auth_user198 on public.hrc_hr_employees(tenant_id,auth_user_id) where auth_user_id is not null;
create or replace function public.unimis_hr_link_employee_user198(p_institution_id uuid,p_employee_id uuid,p_user_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_email text; v_employee uuid;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if not exists(select 1 from public.institution_users iu join public.roles r on r.id=iu.role_id where iu.institution_id=p_institution_id and iu.user_id=auth.uid() and iu.status='active' and lower(r.code) in ('owner','hr_manager','hr_officer')) then raise exception 'HR write access required'; end if;
 if not exists(select 1 from public.institution_users where institution_id=p_institution_id and user_id=p_user_id and status='active') then raise exception 'Selected UniMIS user is not an active member of this institution'; end if;
 select id into v_employee from public.hrc_hr_employees where id=p_employee_id and tenant_id=p_institution_id;
 if v_employee is null then raise exception 'Employee record not found'; end if;
 if exists(select 1 from public.hrc_hr_employees where tenant_id=p_institution_id and auth_user_id=p_user_id and id<>p_employee_id) then raise exception 'This UniMIS user is already linked to another employee record'; end if;
 select email into v_email from auth.users where id=p_user_id;
 if v_email is null then raise exception 'Auth user not found'; end if;
 update public.hrc_hr_employees set auth_user_id=p_user_id,email=coalesce(nullif(email,''),v_email) where id=p_employee_id and tenant_id=p_institution_id;
 return jsonb_build_object('employee_id',p_employee_id,'user_id',p_user_id,'email',v_email,'linked',true);
end $$;
grant execute on function public.unimis_hr_link_employee_user198(uuid,uuid,uuid) to authenticated;
