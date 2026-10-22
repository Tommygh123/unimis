-- Repair View Account: receipt numbers belong to payment_receipts.
begin;

create or replace function public.unimis_student_finance_ledger(p_student_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid:=public.unimis_finance_institution(); v_student jsonb; v_invoices jsonb; v_payments jsonb; v_ledger jsonb;
begin
 if v_inst is null then raise exception 'Finance access required'; end if;
 select jsonb_build_object('id',s.id,'student_number',s.student_number,'name',concat_ws(' ',s.first_name,s.middle_name,s.last_name),'email',s.email,'phone',s.phone,
  'programme_code',p.code,'programme_name',p.name,'level',e.current_level,'student_type',s.student_type)
 into v_student from public.students s left join public.student_programme_enrolments e on e.student_id=s.id and e.is_primary=true left join public.programmes p on p.id=e.programme_id
 where s.id=p_student_id and s.institution_id=v_inst;
 if v_student is null then raise exception 'Student not found'; end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.invoice_date desc),'[]'::jsonb) into v_invoices from (
  select i.id,i.invoice_number,i.invoice_date,i.due_date,i.currency_code,i.total_amount,i.amount_paid,i.balance,i.status,ay.name academic_year,ap.name academic_period
  from public.student_invoices i left join public.academic_years ay on ay.id=i.academic_year_id left join public.academic_periods ap on ap.id=i.academic_period_id
  where i.student_id=p_student_id and i.institution_id=v_inst
 )x;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.payment_date desc),'[]'::jsonb) into v_payments from (
  select p.id,p.payment_date,p.payment_reference,r.receipt_number,p.payment_method,p.amount,p.currency_code,p.status,p.invoice_id
  from public.student_payments p left join public.payment_receipts r on r.payment_id=p.id and r.institution_id=p.institution_id where p.student_id=p_student_id and p.institution_id=v_inst
 )x;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.txn_date,x.sort_no),'[]'::jsonb) into v_ledger from (
  select i.invoice_date::timestamp txn_date,1 sort_no,'invoice' txn_type,i.invoice_number reference,'Fee invoice' description,i.total_amount debit,0::numeric credit,i.currency_code
  from public.student_invoices i where i.student_id=p_student_id and i.institution_id=v_inst and i.status<>'cancelled'
  union all
  select p.payment_date,2,'payment',coalesce(r.receipt_number,p.payment_reference),'Fee payment — '||replace(p.payment_method,'_',' '),0,p.amount,p.currency_code
  from public.student_payments p left join public.payment_receipts r on r.payment_id=p.id and r.institution_id=p.institution_id where p.student_id=p_student_id and p.institution_id=v_inst and p.status='posted'
 )x;
 return jsonb_build_object('student',v_student,'summary',jsonb_build_object(
   'billed',coalesce((select sum(total_amount) from public.student_invoices where student_id=p_student_id and institution_id=v_inst and status<>'cancelled'),0),
   'paid',coalesce((select sum(amount) from public.student_payments where student_id=p_student_id and institution_id=v_inst and status='posted'),0),
   'outstanding',coalesce((select sum(balance) from public.student_invoices where student_id=p_student_id and institution_id=v_inst and status<>'cancelled'),0)
 ),'invoices',v_invoices,'payments',v_payments,'ledger',v_ledger);
end $$;


grant execute on function public.unimis_student_finance_ledger(uuid) to authenticated;
commit;
notify pgrst,'reload schema';
