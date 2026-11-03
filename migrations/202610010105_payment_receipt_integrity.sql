begin;

-- 105: student_payments already has an AFTER INSERT trigger which creates the receipt.
-- The finance RPC must therefore reuse that receipt instead of inserting a second one.
create or replace function public.unimis_record_student_payment(p_payment jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_inst uuid:=public.unimis_finance_institution();
 v_inv public.student_invoices%rowtype;
 v_id uuid; v_seq bigint; v_pay_ref text; v_receipt text; v_amount numeric;
 v_method text; v_new_paid numeric; v_new_bal numeric;
begin
 if v_inst is null then raise exception 'Finance access required'; end if;
 select * into v_inv from public.student_invoices
 where id=(p_payment->>'invoice_id')::uuid and institution_id=v_inst for update;
 if not found then raise exception 'Invoice not found'; end if;

 v_amount:=(p_payment->>'amount')::numeric;
 v_method:=coalesce(nullif(p_payment->>'payment_method',''),'cash');
 if v_amount<=0 then raise exception 'Payment amount must be greater than zero'; end if;
 if v_amount>v_inv.balance then raise exception 'Payment cannot exceed invoice balance'; end if;
 if v_method='mobile_money' and nullif(btrim(coalesce(p_payment->>'reference','')),'') is null then
   raise exception 'MoMo transaction/reference number is required';
 end if;

 -- User/provider references are idempotency keys. If a completed payment with the
 -- same reference already exists, return it instead of posting money twice.
 if nullif(btrim(coalesce(p_payment->>'reference','')),'') is not null then
   select p.id,p.payment_reference into v_id,v_pay_ref
   from public.student_payments p
   where p.institution_id=v_inst
     and p.payment_reference=btrim(p_payment->>'reference')
     and p.status='completed'
   limit 1;
   if v_id is not null then
     select r.receipt_number into v_receipt from public.payment_receipts r where r.payment_id=v_id;
     select i.balance into v_new_bal from public.student_payments p join public.student_invoices i on i.id=p.invoice_id where p.id=v_id;
     return jsonb_build_object('ok',true,'already_posted',true,'payment_id',v_id,'receipt_number',v_receipt,'payment_reference',v_pay_ref,'balance',v_new_bal);
   end if;
 end if;

 insert into public.finance_document_sequences(institution_id,document_type,last_number)
 values(v_inst,'payment',1)
 on conflict(institution_id,document_type) do update
 set last_number=public.finance_document_sequences.last_number+1
 returning last_number into v_seq;

 v_pay_ref:=coalesce(nullif(btrim(p_payment->>'reference'),''),
                     'PAY/'||to_char(current_date,'YYYY')||'/'||lpad(v_seq::text,6,'0'));

 -- This insert fires trg_create_receipt_after_payment. That trigger is the ONE
 -- receipt creator. Do not insert payment_receipts again here.
 insert into public.student_payments(
   institution_id,student_id,invoice_id,payment_reference,payment_date,amount,
   currency_code,payment_method,provider,provider_reference,status,received_by,notes)
 values(
   v_inst,v_inv.student_id,v_inv.id,v_pay_ref,now(),v_amount,v_inv.currency_code,
   v_method,nullif(p_payment->>'provider',''),nullif(p_payment->>'provider_reference',''),
   'completed',auth.uid(),nullif(p_payment->>'notes',''))
 returning id into v_id;

 select r.receipt_number into v_receipt
 from public.payment_receipts r where r.payment_id=v_id;

 -- Recalculate from completed payments rather than incrementing cached totals.
 -- This makes the invoice result deterministic and safe after retries.
 select coalesce(sum(p.amount),0) into v_new_paid
 from public.student_payments p
 where p.invoice_id=v_inv.id and p.status='completed';

 v_new_bal:=greatest(v_inv.total_amount-v_new_paid,0);
 update public.student_invoices
 set amount_paid=v_new_paid,balance=v_new_bal,
     status=case when v_new_bal<=0 then 'paid' when v_new_paid>0 then 'part_paid' else 'unpaid' end,
     updated_at=now()
 where id=v_inv.id;

 perform public.unimis_post_auto_journal(
   'student_payment',v_id,current_date,coalesce(v_receipt,v_pay_ref),
   'Student payment '||coalesce(v_receipt,v_pay_ref),'1000','1100',v_amount);

 return jsonb_build_object(
   'ok',true,'already_posted',false,'payment_id',v_id,'receipt_number',v_receipt,
   'payment_reference',v_pay_ref,'invoice_number',v_inv.invoice_number,
   'amount',v_amount,'amount_paid',v_new_paid,'balance',v_new_bal);
end $$;

grant execute on function public.unimis_record_student_payment(jsonb) to authenticated;

commit;
notify pgrst,'reload schema';
