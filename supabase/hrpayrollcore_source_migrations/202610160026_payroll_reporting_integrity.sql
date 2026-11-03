-- HRPayrollCore 007c: compensation/report reconciliation and payroll-ready reporting view
create or replace view public.payroll_employee_compensation_summary
with (security_invoker=true) as
select e.tenant_id,e.id employee_id,e.employee_no,
       concat_ws(' ',e.first_name,e.other_names,e.last_name) employee_name,
       d.name department_name,
       coalesce(sal.basic_salary,0)::numeric(14,2) basic_salary,
       coalesce(pc.recurring_earnings,0)::numeric(14,2) recurring_earnings,
       coalesce(pc.recurring_deductions,0)::numeric(14,2) recurring_deductions,
       (coalesce(sal.basic_salary,0)+coalesce(pc.recurring_earnings,0))::numeric(14,2) gross_structure,
       (coalesce(sal.basic_salary,0)+coalesce(pc.taxable_earnings,0))::numeric(14,2) taxable_structure,
       coalesce(rel.approved_annual_relief,0)::numeric(14,2) approved_annual_relief,
       round(coalesce(rel.approved_annual_relief,0)/12,2)::numeric(14,2) indicative_monthly_relief,
       (pp.id is not null and coalesce(sal.basic_salary,0)>0) payroll_ready
from public.hr_employees e
left join public.departments d on d.id=e.department_id
left join public.payroll_profiles pp on pp.employee_id=e.id and pp.tenant_id=e.tenant_id and pp.active
left join lateral (
  select coalesce(
    (select sh.new_salary from public.hr_salary_history sh where sh.employee_id=e.id and sh.tenant_id=e.tenant_id and sh.effective_from<=current_date order by sh.effective_from desc,sh.created_at desc limit 1),
    (select c.basic_salary from public.hr_employment_contracts c where c.employee_id=e.id and c.tenant_id=e.tenant_id and c.status='active' and c.start_date<=current_date order by c.start_date desc limit 1),0) basic_salary
) sal on true
left join lateral (
  select coalesce(sum(case when c.component_type='earning' then ec.amount else 0 end),0) recurring_earnings,
         coalesce(sum(case when c.component_type='deduction' then ec.amount else 0 end),0) recurring_deductions,
         coalesce(sum(case when c.component_type='earning' and c.taxable then ec.amount else 0 end),0) taxable_earnings
  from public.payroll_employee_components ec join public.payroll_components c on c.id=ec.component_id
  where ec.tenant_id=e.tenant_id and ec.employee_id=e.id and ec.effective_from<=current_date and (ec.effective_to is null or ec.effective_to>=current_date) and c.active
) pc on true
left join lateral (
  select coalesce(sum(er.approved_annual_amount),0) approved_annual_relief
  from public.payroll_employee_reliefs er
  where er.tenant_id=e.tenant_id and er.employee_id=e.id and er.approved and er.relief_status='active'
    and er.tax_year=extract(year from current_date)::int and er.effective_from<=current_date and (er.effective_to is null or er.effective_to>=current_date)
) rel on true
where e.employment_status='active';

grant select on public.payroll_employee_compensation_summary to authenticated;

comment on view public.payroll_employee_compensation_summary is '007c reconciliation view: current effective salary structure and consolidated approved annual relief. Payroll run results remain immutable after posting.';
