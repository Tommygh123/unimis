-- 009g: richer staff salary payment transaction audit trail.
alter table public.payroll_staff_payment_transactions
  add column if not exists payment_method text,
  add column if not exists notes text,
  add column if not exists batch_reference text;

create index if not exists payroll_staff_payment_transactions_statement_date_idx
  on public.payroll_staff_payment_transactions(statement_id,payment_date desc,created_at desc);

create or replace function public.payroll_record_staff_payment_detailed(
  p_tenant uuid,
  p_statement uuid,
  p_amount numeric,
  p_reference text,
  p_payment_date date default current_date,
  p_method text default 'bank_transfer',
  p_notes text default null,
  p_batch_reference text default null
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare s payroll_staff_statements%rowtype; np numeric; nb numeric;
begin
  if not public.has_tenant_role(p_tenant,array['owner','administrator','accountant','finance_manager','payroll_manager','payroll_officer']) then
    raise exception 'Payroll access denied';
  end if;
  select * into s from payroll_staff_statements where id=p_statement and tenant_id=p_tenant for update;
  if s.id is null then raise exception 'Staff payroll statement not found'; end if;
  if p_amount<=0 or p_amount>s.balance then raise exception 'Payment must be greater than zero and not exceed outstanding balance'; end if;
  if coalesce(trim(p_reference),'')='' then raise exception 'Payment reference is required'; end if;
  insert into payroll_staff_payment_transactions(tenant_id,statement_id,amount,payment_date,reference,payment_method,notes,batch_reference)
  values(p_tenant,p_statement,p_amount,coalesce(p_payment_date,current_date),trim(p_reference),coalesce(nullif(trim(p_method),''),'other'),nullif(trim(p_notes),''),nullif(trim(p_batch_reference),''));
  np:=s.amount_paid+p_amount; nb:=greatest(s.amount_due-np,0);
  update payroll_staff_statements set amount_paid=np,balance=nb,status=case when nb=0 then 'paid' else 'part_paid' end,last_payment_date=coalesce(p_payment_date,current_date),last_payment_reference=trim(p_reference),updated_at=now() where id=s.id;
  return jsonb_build_object('ok',true,'paid',np,'balance',nb,'statement_id',s.id);
end$$;
grant execute on function public.payroll_record_staff_payment_detailed(uuid,uuid,numeric,text,date,text,text,text) to authenticated;
notify pgrst,'reload schema';
