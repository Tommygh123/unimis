-- UniMIS Build 167: bridge UniMIS institution identity/RBAC into HRPayrollCore.
-- Requires the HRPayrollCore schema migrations to be installed in the same schema first.
create or replace function public.unimis_hrpayroll_context167()
returns table(tenant_id uuid,institution_name text,institution_code text,hr_role text)
language plpgsql security definer set search_path=public as $$
declare v_inst uuid; v_name text; v_code text; v_role text; v_hr_role text;
begin
 select m.institution_id,i.name,i.code,r.code
 into v_inst,v_name,v_code,v_role
 from public.unimis_effective_memberships116 m
 join public.institutions i on i.id=m.institution_id
 join public.roles r on r.id=m.role_id
 where m.user_id=auth.uid() and m.status='active' and r.is_active
 order by m.is_primary desc limit 1;
 if v_inst is null then return; end if;
 v_hr_role:=case
  when v_role='owner' then 'owner'
  when v_role in ('admin','administrator','registrar') then 'administrator'
  when v_role='hr_officer' then 'hr_officer'
  when v_role='payroll_officer' then 'payroll_officer'
  when v_role in ('finance_officer','accountant') then 'accountant'
  when v_role='auditor' then 'auditor'
  else 'employee' end;
 insert into public.tenants(id,name,code,hr_enabled,payroll_enabled,created_by)
 values(v_inst,v_name,coalesce(nullif(v_code,''),'UNI-'||left(v_inst::text,8)),true,true,auth.uid())
 on conflict(id) do update set name=excluded.name,hr_enabled=true,payroll_enabled=true;
 insert into public.tenant_memberships(tenant_id,user_id,role,status)
 values(v_inst,auth.uid(),v_hr_role,'active')
 on conflict(tenant_id,user_id) do update set role=excluded.role,status='active';
 return query select v_inst,v_name,v_code,v_hr_role;
end $$;
grant execute on function public.unimis_hrpayroll_context167() to authenticated;
