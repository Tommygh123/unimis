-- HRPayrollCore 008e: complete posted-payroll liabilities for settlement/remittance.
-- Idempotent: recreates liabilities for a run only when none exist.
create or replace function public.payroll_generate_payment_liabilities(p_tenant uuid,p_run uuid)
returns integer language plpgsql security definer set search_path=public as $$
declare r record; n integer:=0; v numeric;
begin
  if not exists(select 1 from tenant_memberships m where m.tenant_id=p_tenant and m.user_id=auth.uid() and m.status='active' and m.role in ('owner','administrator','accountant','finance_manager','payroll_manager','payroll_officer')) then raise exception 'Payroll access denied'; end if;
  select pr.*,pp.end_date into r from payroll_runs pr left join payroll_periods pp on pp.id=pr.period_id where pr.id=p_run and pr.tenant_id=p_tenant;
  if not found then raise exception 'Payroll run not found'; end if;
  if r.status<>'posted' then raise exception 'Payroll must be posted before liabilities can be generated'; end if;
  if exists(select 1 from payroll_payment_liabilities where tenant_id=p_tenant and payroll_run_id=p_run) then return 0; end if;

  select coalesce(sum(net_pay),0) into v from payroll_run_employees where run_id=p_run;
  if v>0 then insert into payroll_payment_liabilities(tenant_id,payroll_run_id,liability_type,payee_name,amount,balance,status,due_date) values(p_tenant,p_run,'employee_salary','Employees / Salary Payable',v,v,'unpaid',r.end_date); n:=n+1; end if;
  select coalesce(sum(tax),0) into v from payroll_run_employees where run_id=p_run;
  if v>0 then insert into payroll_payment_liabilities(tenant_id,payroll_run_id,liability_type,payee_name,amount,balance,status,due_date) values(p_tenant,p_run,'paye','GRA / PAYE Payable',v,v,'unpaid',r.end_date); n:=n+1; end if;
  select coalesce(sum(tier1_total),0) into v from payroll_run_employees where run_id=p_run;
  if v>0 then insert into payroll_payment_liabilities(tenant_id,payroll_run_id,liability_type,payee_name,amount,balance,status,due_date) values(p_tenant,p_run,'ssnit','SSNIT / Tier 1 Payable',v,v,'unpaid',r.end_date); n:=n+1; end if;
  select coalesce(sum(tier2_total),0) into v from payroll_run_employees where run_id=p_run;
  if v>0 then insert into payroll_payment_liabilities(tenant_id,payroll_run_id,liability_type,payee_name,amount,balance,status,due_date) values(p_tenant,p_run,'tier2','Tier 2 Trustee Payable',v,v,'unpaid',r.end_date); n:=n+1; end if;
  select coalesce(sum(provident_employee),0) into v from payroll_run_employees where run_id=p_run;
  if v>0 then insert into payroll_payment_liabilities(tenant_id,payroll_run_id,liability_type,payee_name,amount,balance,status,due_date) values(p_tenant,p_run,'tier3','Tier 3 / Provident Fund Payable',v,v,'unpaid',r.end_date); n:=n+1; end if;
  select coalesce(sum(other_deductions),0) into v from payroll_run_employees where run_id=p_run;
  if v>0 then insert into payroll_payment_liabilities(tenant_id,payroll_run_id,liability_type,payee_name,amount,balance,status,due_date) values(p_tenant,p_run,'third_party','Third-party / Agreed Deductions Payable',v,v,'unpaid',r.end_date); n:=n+1; end if;
  return n;
end $$;
grant execute on function public.payroll_generate_payment_liabilities(uuid,uuid) to authenticated;
