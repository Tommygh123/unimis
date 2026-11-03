-- UniMIS Build 173: deterministic HR/Payroll bridge for shared remote schema.
-- Uses the institution already selected by native UniMIS UserContext.
set search_path=public;

drop function if exists public.unimis_hrpayroll_context173(uuid);

create function public.unimis_hrpayroll_context173(p_institution_id uuid)
returns table(tenant_id uuid,institution_name text,institution_code text,hr_role text)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_name text;
  v_code text;
  v_role text;
  v_hr_role text;
begin
  if auth.uid() is null or p_institution_id is null then
    return;
  end if;

  -- Read the canonical UniMIS membership directly. Do not depend on the
  -- effective-membership view for the primary institution bridge.
  select i.name::text, i.code::text, lower(r.code)
    into v_name, v_code, v_role
  from public.institution_users m
  join public.institutions i on i.id=m.institution_id
  join public.roles r on r.id=m.role_id
  where m.user_id=auth.uid()
    and m.institution_id=p_institution_id
    and coalesce(m.status,'active')='active'
    and coalesce(r.is_active,true)
  order by m.is_primary desc nulls last, m.created_at
  limit 1;

  if v_name is null then
    return;
  end if;

  v_hr_role := case
    when v_role='owner' then 'owner'
    when v_role in ('admin','administrator','registrar') then 'administrator'
    when v_role in ('hr_manager','hr_officer') then v_role
    when v_role in ('payroll_manager','payroll_officer') then v_role
    when v_role in ('finance_officer','accountant') then 'finance_manager'
    when v_role='auditor' then 'auditor'
    else 'employee'
  end;

  insert into public.hrc_tenants(id,name,code,hr_enabled,payroll_enabled,created_by)
  values(p_institution_id,v_name,coalesce(nullif(v_code,''),'UNI-'||left(p_institution_id::text,8)),true,true,auth.uid())
  on conflict(id) do update
    set name=excluded.name, code=excluded.code, hr_enabled=true, payroll_enabled=true;

  insert into public.hrc_tenant_memberships(tenant_id,user_id,role,status)
  values(p_institution_id,auth.uid(),v_hr_role,'active')
  on conflict(tenant_id,user_id) do update
    set role=excluded.role,status='active';

  return query
  select p_institution_id,v_name,v_code,
         case when v_role in ('finance_officer','accountant') then 'accountant'
              else v_hr_role end;
end
$$;

grant execute on function public.unimis_hrpayroll_context173(uuid) to authenticated;
select pg_notify('pgrst','reload schema');
