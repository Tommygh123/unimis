-- HRPayrollCore 009a - Payroll Classification & Pension Status Workspace
-- Safe effective-dated classification setter and employee Tier 3 metadata.

alter table public.payroll_profiles
  add column if not exists provident_member_reference text,
  add column if not exists provident_effective_from date,
  add column if not exists provident_effective_to date;

insert into public.payroll_pension_review_rules
  (tenant_id,country_code,review_age,label,message,active,effective_from)
select t.id,'GH',55,'Pension status review',
       'Employee has reached a configured pension milestone. Review contributor/pension status before payroll. No deduction is changed automatically.',
       true,current_date
from public.tenants t
where not exists (
  select 1 from public.payroll_pension_review_rules r
  where r.tenant_id=t.id and r.country_code='GH' and r.active=true
);

create or replace function public.payroll_set_worker_classification(
  p_tenant uuid,
  p_employee uuid,
  p_employment_relationship text,
  p_tax_treatment text,
  p_pension_status text,
  p_tier3_participation text,
  p_pay_frequency text,
  p_effective_from date,
  p_reason text default null,
  p_evidence_reference text default null
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_id uuid;
  v_existing public.payroll_worker_classifications%rowtype;
begin
  if not public.is_tenant_member(p_tenant) then
    raise exception 'Tenant access denied';
  end if;
  if not exists(select 1 from public.hr_employees where id=p_employee and tenant_id=p_tenant) then
    raise exception 'Employee does not belong to this tenant';
  end if;

  select * into v_existing
  from public.payroll_worker_classifications
  where tenant_id=p_tenant and employee_id=p_employee and effective_to is null
  order by effective_from desc limit 1;

  if v_existing.id is not null then
    if p_effective_from < v_existing.effective_from then
      raise exception 'New effective date cannot be earlier than the current classification effective date';
    elsif p_effective_from = v_existing.effective_from then
      update public.payroll_worker_classifications
      set employment_relationship=p_employment_relationship,
          tax_treatment=p_tax_treatment,
          pension_status=p_pension_status,
          tier3_participation=p_tier3_participation,
          pay_frequency=p_pay_frequency,
          reason=p_reason,
          evidence_reference=p_evidence_reference,
          updated_at=now()
      where id=v_existing.id
      returning id into v_id;
      return v_id;
    else
      update public.payroll_worker_classifications
      set effective_to=p_effective_from-1, updated_at=now()
      where id=v_existing.id;
    end if;
  end if;

  insert into public.payroll_worker_classifications(
    tenant_id,employee_id,employment_relationship,tax_treatment,pension_status,
    tier3_participation,pay_frequency,effective_from,reason,evidence_reference
  ) values(
    p_tenant,p_employee,p_employment_relationship,p_tax_treatment,p_pension_status,
    p_tier3_participation,p_pay_frequency,p_effective_from,p_reason,p_evidence_reference
  ) returning id into v_id;

  update public.payroll_profiles
  set tier3_participation_mode=p_tier3_participation
  where tenant_id=p_tenant and employee_id=p_employee;

  return v_id;
end $$;

grant execute on function public.payroll_set_worker_classification(
  uuid,uuid,text,text,text,text,text,date,text,text
) to authenticated;
