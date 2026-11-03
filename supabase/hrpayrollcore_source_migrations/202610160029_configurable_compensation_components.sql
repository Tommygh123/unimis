-- HRPayrollCore 007e: configurable compensation components and agreed deductions
alter table public.payroll_components
 add column if not exists employee_or_employer text not null default 'employee',
 add column if not exists requires_consent boolean not null default false,
 add column if not exists requires_approval boolean not null default false,
 add column if not exists effective_from date not null default current_date,
 add column if not exists effective_to date,
 add column if not exists description text;

do $$ begin
  if not exists(select 1 from pg_constraint where conname='payroll_components_employee_or_employer_chk') then
    alter table public.payroll_components add constraint payroll_components_employee_or_employer_chk check(employee_or_employer in ('employee','employer','both'));
  end if;
end $$;

-- Organization-editable agreed deductions. These are ordinary payroll components, so the existing calculation engine consumes them.
insert into public.payroll_components(tenant_id,code,name,component_type,taxable,pensionable,calculation_type,default_amount,tax_treatment,pre_tax,recurring,active,employee_or_employer,requires_consent,requires_approval,effective_from,description)
select t.id,v.code,v.name,'deduction',false,false,'fixed',v.amount,'post_tax',false,true,true,'employee',v.consent,true,'2026-10-01',v.description
from public.tenants t cross join (values
 ('WELFARE','Staff Welfare',50::numeric,true,'Agreed staff welfare contribution'),
 ('STAFF_ASSOC','Staff Association',25::numeric,true,'Agreed staff association contribution'),
 ('UNION','Union Dues',0::numeric,true,'Union or professional association dues'),
 ('CREDIT_UNION','Credit Union',0::numeric,true,'Employee credit union contribution'),
 ('STAFF_INS','Staff Insurance',0::numeric,true,'Employee agreed insurance deduction'),
 ('STAFF_BUS','Staff Transport',0::numeric,true,'Staff transport recovery')
) v(code,name,amount,consent,description)
on conflict(tenant_id,code) do update set component_type='deduction',recurring=true,active=true,employee_or_employer='employee',requires_consent=excluded.requires_consent,requires_approval=true,description=excluded.description;

-- Make common recurring earnings explicit and organization-editable.
update public.payroll_components set recurring=true, employee_or_employer='employee', requires_approval=true
where code in ('TRANSPORT','ACCOM','RISK','NIGHT','RESP','CHILD-ALLOW','HOUSEHELP','COOK','GARDEN') and component_type='earning';

-- Overtime and bonus are variable inputs, not recurring compensation components.
update public.payroll_components set recurring=false where code in ('OT','OVERTIME','BONUS');

notify pgrst, 'reload schema';
