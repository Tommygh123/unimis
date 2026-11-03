-- HRPayrollCore 007e2: unified payroll component catalogue
-- The old payroll_deduction_definitions table is retained only for historical compatibility.
-- New configuration is performed exclusively through payroll_components.

-- Migrate any organization-specific deductions created in the old settings form (e.g. T & T)
-- into the universal component catalogue without assigning them to any employee.
insert into public.payroll_components(
  tenant_id,code,name,component_type,taxable,pensionable,calculation_type,default_amount,
  tax_treatment,pre_tax,recurring,active,employee_or_employer,requires_consent,requires_approval,
  effective_from,effective_to,description
)
select d.tenant_id, upper(replace(trim(d.code),' ','_')), d.name,
       'deduction',
       false,false,d.calculation_method,d.default_value,
       case when d.pre_tax then 'pre_tax' else 'post_tax' end,d.pre_tax,d.recurring,d.active,
       d.employee_or_employer,d.requires_consent,d.requires_approval,d.effective_from,d.effective_to,d.description
from public.payroll_deduction_definitions d
on conflict(tenant_id,code) do update set
  name=excluded.name,
  component_type=excluded.component_type,
  calculation_type=excluded.calculation_type,
  default_amount=excluded.default_amount,
  pre_tax=excluded.pre_tax,
  recurring=excluded.recurring,
  active=excluded.active,
  employee_or_employer=excluded.employee_or_employer,
  requires_consent=excluded.requires_consent,
  requires_approval=excluded.requires_approval,
  effective_from=excluded.effective_from,
  effective_to=excluded.effective_to,
  description=coalesce(excluded.description,public.payroll_components.description);

-- Safety rule: a component existing/enabled in Settings never means it is assigned to all staff.
-- Employee application remains explicit in payroll_employee_components.

insert into public.hrpay_audit_events(tenant_id,domain,action,entity_type,entity_reference,actor_label,new_data)
select t.id,'payroll','component_catalogue_unified','payroll_settings','007E2','System',
       jsonb_build_object('package','007e2','rule','Enabled catalogue components require explicit employee assignment')
from public.tenants t
where not exists(select 1 from public.hrpay_audit_events a where a.tenant_id=t.id and a.entity_reference='007E2');

notify pgrst, 'reload schema';
