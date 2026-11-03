-- HRPayrollCore 008e3: safe development/test reset for a posted payroll run.
-- This is intentionally explicit and auditable. It refuses to reset any run
-- for which a payment/remittance amount has already been recorded.

create table if not exists public.payroll_test_reset_audit (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  payroll_run_id uuid not null,
  run_no text,
  previous_status text,
  reset_by uuid default auth.uid(),
  reset_at timestamptz not null default now(),
  note text not null default 'Reset payroll run for controlled workflow testing'
);

alter table public.payroll_test_reset_audit enable row level security;

drop policy if exists payroll_test_reset_audit_select on public.payroll_test_reset_audit;
create policy payroll_test_reset_audit_select on public.payroll_test_reset_audit
for select using (
  exists (select 1 from public.tenant_memberships tm
          where tm.tenant_id=payroll_test_reset_audit.tenant_id
            and tm.user_id=auth.uid() and tm.status='active')
);

create or replace function public.payroll_reset_run_for_testing(p_tenant uuid, p_run uuid)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_run public.payroll_runs%rowtype;
  v_paid numeric := 0;
  v_liabilities integer := 0;
begin
  if not exists (
    select 1 from public.tenant_memberships tm
    where tm.tenant_id=p_tenant and tm.user_id=auth.uid() and tm.status='active'
      and tm.role in ('owner','administrator','accountant','payroll_manager','payroll_officer','finance_manager')
  ) then
    raise exception 'Payroll access denied';
  end if;

  select * into v_run from public.payroll_runs
   where id=p_run and tenant_id=p_tenant for update;
  if not found then raise exception 'Payroll run not found'; end if;
  if v_run.status <> 'posted' then
    raise exception 'Only a posted payroll run can be reset with this testing control';
  end if;

  if to_regclass('public.payroll_payment_liabilities') is not null then
    execute 'select coalesce(sum(coalesce(amount_paid,0)),0) from public.payroll_payment_liabilities where tenant_id=$1 and payroll_run_id=$2'
      into v_paid using p_tenant,p_run;
    if v_paid > 0 then
      raise exception 'Reset blocked: this payroll has recorded payments/remittances totaling GH₵%. Reverse those payments first.', v_paid;
    end if;
    execute 'select count(*) from public.payroll_payment_liabilities where tenant_id=$1 and payroll_run_id=$2'
      into v_liabilities using p_tenant,p_run;
    execute 'delete from public.payroll_payment_liabilities where tenant_id=$1 and payroll_run_id=$2'
      using p_tenant,p_run;
  end if;

  insert into public.payroll_test_reset_audit(tenant_id,payroll_run_id,run_no,previous_status)
  values(p_tenant,p_run,v_run.run_no,v_run.status);

  delete from public.payroll_run_employees where run_id=p_run;

  update public.payroll_runs
     set status='draft', employee_count=0, gross_total=0, tax_total=0, net_total=0,
         employee_pension_total=0, employer_pension_total=0
   where id=p_run and tenant_id=p_tenant;

  -- Re-open the linked period when the schema uses the standard period_id column.
  update public.payroll_periods p set status='open'
   where p.id=v_run.period_id and p.tenant_id=p_tenant;

  return jsonb_build_object(
    'ok',true,'run_no',v_run.run_no,'status','draft',
    'cleared_liabilities',v_liabilities,
    'message','Payroll reset to Draft. Start with Calculate / Recalculate.'
  );
end;
$$;

grant execute on function public.payroll_reset_run_for_testing(uuid,uuid) to authenticated;
