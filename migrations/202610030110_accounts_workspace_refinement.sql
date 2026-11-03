begin;

-- Read-only reporting over existing transactions. No duplicate accounting tables.
create or replace function public.unimis_finance_analytics_workspace(p_filters jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_inst uuid := public.unimis_finance_institution();
 v_from date := coalesce(nullif(p_filters->>'from','')::date,date_trunc('year',current_date)::date);
 v_to date := coalesce(nullif(p_filters->>'to','')::date,current_date);
 v_currency text := coalesce(nullif(p_filters->>'currency',''),'GHS');
 v_result jsonb;
begin
 if v_inst is null then raise exception 'Finance access required'; end if;
 if v_from>v_to then raise exception 'From date must be on or before To date'; end if;
 with cohort as (
  select i.*,s.student_number,concat_ws(' ',s.first_name,s.middle_name,s.last_name) student_name,
   s.student_type,e.programme_id,e.current_level level,p.code programme_code,
   coalesce((select sum(ii.line_total) from public.student_invoice_items ii
     where ii.invoice_id=i.id and ii.institution_id=v_inst
     and (nullif(p_filters->>'fee_type_id','') is null or ii.fee_type_id=(p_filters->>'fee_type_id')::uuid)),0) component_total,
   coalesce((select sum(sp.amount) from public.student_payments sp where sp.invoice_id=i.id
     and sp.institution_id=v_inst and sp.currency_code=v_currency and sp.status='completed' and sp.payment_method<>'waiver' and sp.payment_date::date<=v_to),0) paid_asof
   ,i.total_amount+i.discount_amount gross_billed,
   i.discount_amount+coalesce((select sum(w.amount) from public.student_payments w where w.invoice_id=i.id and w.institution_id=v_inst and w.status='completed' and w.payment_method='waiver' and w.payment_date::date<=v_to),0)
    +case when i.status='waived' then greatest(i.total_amount-coalesce((select sum(w.amount) from public.student_payments w where w.invoice_id=i.id and w.institution_id=v_inst and w.status='completed' and w.payment_date::date<=v_to),0),0) else 0 end waiver_asof
  from public.student_invoices i join public.students s on s.id=i.student_id and s.institution_id=v_inst
  left join lateral (select en.programme_id,en.current_level from public.student_programme_enrolments en
    where en.student_id=s.id and en.institution_id=v_inst and en.is_primary=true order by en.id limit 1) e on true
  left join public.programmes p on p.id=e.programme_id and p.institution_id=v_inst
  where i.institution_id=v_inst and i.currency_code=v_currency and i.status<>'cancelled'
    and i.invoice_date between v_from and v_to
    and (nullif(p_filters->>'academic_year_id','') is null or i.academic_year_id=(p_filters->>'academic_year_id')::uuid)
    and (nullif(p_filters->>'academic_period_id','') is null or i.academic_period_id=(p_filters->>'academic_period_id')::uuid)
    and (nullif(p_filters->>'programme_id','') is null or e.programme_id=(p_filters->>'programme_id')::uuid)
    and (nullif(p_filters->>'level','') is null or e.current_level=(p_filters->>'level')::integer)
    and (nullif(p_filters->>'student_type','') is null or s.student_type=p_filters->>'student_type')
 ), invoices as (
  select c.*,case when nullif(p_filters->>'fee_type_id','') is null then 1::numeric
   else c.component_total/nullif(c.gross_billed,0) end weight
  from cohort c where (nullif(p_filters->>'fee_type_id','') is null or c.component_total>0)
   and (coalesce(p_filters->>'status','')='' or
    (p_filters->>'status'='outstanding' and c.status<>'waived' and c.gross_billed>c.paid_asof+c.waiver_asof) or
    (p_filters->>'status'='settled' and (c.status='waived' or c.gross_billed<=c.paid_asof+c.waiver_asof)))
 ), payments as (
  select sp.payment_date::date payment_date,sp.payment_reference,sp.payment_method,
   sp.amount*i.weight amount,i.student_number,i.student_name,i.programme_code,i.level,i.student_id
  from public.student_payments sp join invoices i on i.id=sp.invoice_id
  where sp.institution_id=v_inst and sp.currency_code=v_currency and sp.status='completed' and sp.payment_method<>'waiver'
   and sp.payment_date::date between v_from and v_to
   and (nullif(p_filters->>'payment_method','') is null or sp.payment_method=p_filters->>'payment_method')
 ), student_totals as (
  select student_id,student_number,student_name,programme_code,level,student_type,
   sum(gross_billed*weight) billed,sum(least(paid_asof,gross_billed)*weight) paid,sum(waiver_asof*weight) waiver,
   sum(greatest(gross_billed-paid_asof-waiver_asof,0)*weight) outstanding
  from invoices group by student_id,student_number,student_name,programme_code,level,student_type
 ), components as (
  select ii.fee_type_id,coalesce(ft.name,ii.description) fee_type,count(distinct i.student_id) students,
   sum(ii.line_total) billed,
   sum(ii.line_total*least(i.paid_asof,i.gross_billed)/nullif(i.gross_billed,0)) paid,
   sum(ii.line_total*i.waiver_asof/nullif(i.gross_billed,0)) waiver,
   sum(ii.line_total*greatest(i.gross_billed-i.paid_asof-i.waiver_asof,0)/nullif(i.gross_billed,0)) outstanding
  from invoices i join public.student_invoice_items ii on ii.invoice_id=i.id and ii.institution_id=v_inst
  left join public.fee_types ft on ft.id=ii.fee_type_id and ft.institution_id=v_inst
  where nullif(p_filters->>'fee_type_id','') is null or ii.fee_type_id=(p_filters->>'fee_type_id')::uuid
  group by ii.fee_type_id,coalesce(ft.name,ii.description)
 ), expenses as (
  select expense_date,reference,description,payee,payment_method,amount
  from public.finance_expenses where institution_id=v_inst and currency_code=v_currency
   and status='posted' and expense_date between v_from and v_to
 ), ledger as (
  select j.journal_date,j.journal_number,j.reference,a.code,a.name,a.account_type,
   coalesce(l.description,j.description) description,l.debit,l.credit
  from public.finance_journals j join public.finance_journal_lines l on l.journal_id=j.id and l.institution_id=v_inst
  join public.finance_accounts a on a.id=l.account_id and a.institution_id=v_inst
  where j.institution_id=v_inst and j.status='posted' and j.journal_date between v_from and v_to
 ), balances as (
  select a.code,a.name,a.account_type,a.normal_balance,sum(l.debit) debit,sum(l.credit) credit
  from public.finance_journals j join public.finance_journal_lines l on l.journal_id=j.id and l.institution_id=v_inst
  join public.finance_accounts a on a.id=l.account_id and a.institution_id=v_inst
  where j.institution_id=v_inst and j.status='posted' and j.journal_date<=v_to
  group by a.id,a.code,a.name,a.account_type,a.normal_balance
 )
 select jsonb_build_object(
  'summary',jsonb_build_object('billed',coalesce((select sum(billed) from student_totals),0),
   'paid',coalesce((select sum(paid) from student_totals),0),'waiver',coalesce((select sum(waiver) from student_totals),0),
   'collected',coalesce((select sum(amount) from payments),0),
   'outstanding',coalesce((select sum(outstanding) from student_totals),0),
   'expenses',coalesce((select sum(amount) from expenses),0)),
  'invoices',coalesce((select jsonb_agg(to_jsonb(x) order by x.invoice_date) from (select student_id,invoice_date,invoice_number,gross_billed*weight billed,least(paid_asof,gross_billed)*weight paid,waiver_asof*weight waiver,greatest(gross_billed-paid_asof-waiver_asof,0)*weight outstanding,status from invoices)x),'[]'::jsonb),
  'students',coalesce((select jsonb_agg(to_jsonb(x) order by x.student_number) from student_totals x),'[]'::jsonb),
  'fee_components',coalesce((select jsonb_agg(to_jsonb(x) order by x.billed desc) from components x),'[]'::jsonb),
  'payments',coalesce((select jsonb_agg(to_jsonb(x) order by x.payment_date desc) from payments x),'[]'::jsonb),
  'trend',coalesce((select jsonb_agg(to_jsonb(x) order by x."month") from (
   select to_char(payment_date,'YYYY-MM') AS "month",sum(amount) amount from payments group by 1)x),'[]'::jsonb),
  'methods',coalesce((select jsonb_agg(to_jsonb(x) order by x.amount desc) from (
   select payment_method,count(*) transactions,sum(amount) amount from payments group by payment_method)x),'[]'::jsonb),
  'programmes',coalesce((select jsonb_agg(to_jsonb(x) order by x.outstanding desc) from (
   select programme_code,level,sum(billed) billed,sum(paid) paid,sum(waiver) waiver,sum(outstanding) outstanding
   from student_totals group by programme_code,level)x),'[]'::jsonb),
  'expenses',coalesce((select jsonb_agg(to_jsonb(x) order by x.expense_date desc) from expenses x),'[]'::jsonb),
  'ledger',coalesce((select jsonb_agg(to_jsonb(x) order by x.journal_date,x.journal_number,x.code) from ledger x),'[]'::jsonb),
  'trial_balance',coalesce((select jsonb_agg(to_jsonb(x) order by x.code) from (
   select code,name,sum(debit) debit,sum(credit) credit,sum(debit-credit) balance from ledger group by code,name)x),'[]'::jsonb),
  'income',coalesce((select jsonb_agg(to_jsonb(x) order by x.code) from (
   select code,name,account_type,sum(case when account_type='income' then credit-debit else debit-credit end) amount
   from ledger where account_type in ('income','expense') group by code,name,account_type)x),'[]'::jsonb),
  'position',coalesce((select jsonb_agg(to_jsonb(x) order by x.code) from (
   select code,name,account_type,case when account_type='asset' then debit-credit else credit-debit end amount
   from balances where account_type in ('asset','liability','equity')
   union all select '','Current / retained earnings','equity',coalesce(sum(credit-debit),0)
   from balances where account_type in ('income','expense'))x),'[]'::jsonb)
 ) into v_result;
 return v_result;
end $$;
create or replace function public.unimis_finance_analytics_filter_options()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid:=public.unimis_finance_institution();
begin
 if v_inst is null then raise exception 'Finance access required'; end if;
 return public.unimis_finance_analytics_filters() || jsonb_build_object(
  'academic_years',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'start_date',start_date,'end_date',end_date,'is_current',is_current) order by is_current desc,start_date desc) from public.academic_years where institution_id=v_inst),'[]'::jsonb),
  'periods',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'academic_year_id',academic_year_id,'start_date',start_date,'end_date',end_date,'is_current',is_current) order by is_current desc,start_date desc) from public.academic_periods where institution_id=v_inst),'[]'::jsonb),
  'student_types',coalesce((select jsonb_agg(x.student_type order by x.student_type) from
   (select distinct student_type from public.students where institution_id=v_inst and student_type is not null)x),'[]'::jsonb),
  'levels',coalesce((select jsonb_agg(x.current_level order by x.current_level) from
   (select distinct e.current_level from public.student_programme_enrolments e join public.students s on s.id=e.student_id
    where s.institution_id=v_inst and e.is_primary=true and e.current_level is not null)x),'[]'::jsonb)
 );
end $$;
revoke all on function public.unimis_finance_analytics_filter_options() from public,anon;
grant execute on function public.unimis_finance_analytics_filter_options() to authenticated;
revoke all on function public.unimis_finance_analytics_workspace(jsonb) from public,anon;
grant execute on function public.unimis_finance_analytics_workspace(jsonb) to authenticated;

-- Link authorised concessions to their invoice using the existing aid records.
alter table public.student_financial_aid add column if not exists invoice_id uuid references public.student_invoices(id);
alter table public.student_financial_aid add column if not exists approval_reference text;
alter table public.student_financial_aid add column if not exists approved_by uuid references auth.users(id);
create unique index if not exists financial_aid_approval_reference110 on public.student_financial_aid(institution_id,approval_reference) where approval_reference is not null;

create or replace function public.unimis_apply_invoice_waiver(p_invoice_id uuid,p_amount numeric,p_reference text,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid:=public.unimis_finance_institution(); v_inv public.student_invoices%rowtype; v_id uuid; v_old public.student_financial_aid%rowtype;
begin
 if v_inst is null then raise exception 'Finance access required'; end if;
 if p_amount is null or p_amount<=0 or p_amount<>round(p_amount,2) then raise exception 'Enter a positive amount with at most two decimal places'; end if;
 if nullif(btrim(p_reference),'') is null or nullif(btrim(p_reason),'') is null then raise exception 'Approval reference and reason are required'; end if;
 select * into v_inv from public.student_invoices where id=p_invoice_id and institution_id=v_inst for update;
 if not found then raise exception 'Invoice not found'; end if;
 select * into v_old from public.student_financial_aid where institution_id=v_inst and approval_reference=btrim(p_reference);
 if found then
  if v_old.invoice_id<>p_invoice_id or v_old.amount<>p_amount then raise exception 'Approval reference already used for another adjustment'; end if;
  return jsonb_build_object('ok',true,'already_applied',true);
 end if;
 if v_inv.status in ('cancelled','draft','waived') or p_amount>v_inv.balance then raise exception 'Waiver must not exceed an active invoice balance'; end if;
 if v_inv.currency_code<>'GHS' then raise exception 'Waiver posting currently supports GHS invoices'; end if;
 insert into public.student_financial_aid(institution_id,student_id,academic_year_id,aid_type,amount,status,start_date,notes,invoice_id,approval_reference,approved_by)
 values(v_inst,v_inv.student_id,v_inv.academic_year_id,'waiver',p_amount,'active',current_date,btrim(p_reason),v_inv.id,btrim(p_reference),auth.uid()) returning id into v_id;
 update public.student_invoices set discount_amount=discount_amount+p_amount,total_amount=total_amount-p_amount,balance=greatest(balance-p_amount,0),
  status=case when balance-p_amount<=0 then 'waived' when amount_paid>0 then 'part_paid' else 'unpaid' end,updated_at=now() where id=v_inv.id;
 perform public.unimis_post_auto_journal('fee_waiver',v_id,current_date,btrim(p_reference),btrim(p_reason),'4000','1100',p_amount);
 return jsonb_build_object('ok',true,'waiver_id',v_id,'balance',greatest(v_inv.balance-p_amount,0));
end $$;
revoke all on function public.unimis_apply_invoice_waiver(uuid,numeric,text,text) from public,anon;
grant execute on function public.unimis_apply_invoice_waiver(uuid,numeric,text,text) to authenticated;

create or replace function public.unimis_finance_operation_checks(p_from date,p_to date)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid:=public.unimis_finance_institution();
begin
 if v_inst is null then raise exception 'Finance access required'; end if;
 if p_from>p_to then raise exception 'Invalid period'; end if;
 return jsonb_build_object(
  'invoices',coalesce((select jsonb_agg(to_jsonb(x) order by x.student_number) from (
   select i.id,i.invoice_number,i.balance,s.student_number,concat_ws(' ',s.first_name,s.last_name) student_name from public.student_invoices i join public.students s on s.id=i.student_id
   where i.institution_id=v_inst and i.currency_code='GHS' and i.balance>0 and i.status not in ('draft','cancelled','waived'))x),'[]'::jsonb),
  'waivers',coalesce((select jsonb_agg(to_jsonb(x) order by x.start_date desc) from (
   select a.start_date,a.approval_reference,a.amount,a.notes,i.invoice_number,s.student_number from public.student_financial_aid a join public.student_invoices i on i.id=a.invoice_id join public.students s on s.id=a.student_id
   where a.institution_id=v_inst and a.aid_type='waiver' and a.start_date between p_from and p_to)x),'[]'::jsonb),
  'methods',coalesce((select jsonb_agg(to_jsonb(x)) from (
   select payment_method,sum(amount) amount,count(*) transactions from public.student_payments where institution_id=v_inst and currency_code='GHS' and status='completed' and payment_method<>'waiver' and payment_date::date between p_from and p_to group by payment_method)x),'[]'::jsonb)
 );
end $$;
revoke all on function public.unimis_finance_operation_checks(date,date) from public,anon;
grant execute on function public.unimis_finance_operation_checks(date,date) to authenticated;
commit;
notify pgrst,'reload schema';
