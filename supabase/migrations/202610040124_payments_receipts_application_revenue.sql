begin;
alter table public.student_payments add column if not exists voided_at timestamptz;
alter table public.student_payments add column if not exists voided_by uuid references auth.users(id);
alter table public.student_payments add column if not exists void_reason text;
alter table public.student_payments add column if not exists replaces_payment_id uuid references public.student_payments(id);
alter table public.student_payments add column if not exists client_request_id uuid;
create unique index if not exists uq_payment_request124 on public.student_payments(institution_id,client_request_id) where client_request_id is not null;
create unique index if not exists uq_payment_replacement124 on public.student_payments(replaces_payment_id) where replaces_payment_id is not null;

create or replace function public.unimis_payment_write_access124()
returns uuid language plpgsql stable security definer set search_path='' as $$
declare inst uuid:=public.unimis_finance_institution();
begin
 if auth.uid() is null or inst is null or not public.has_permission(inst,'finance.manage') or exists(
 select 1 from public.unimis_effective_memberships116 m join public.roles r on r.id=m.role_id
 where m.user_id=auth.uid() and m.institution_id=inst and m.status='active' and lower(r.code)='auditor') then
 raise exception 'Payment management requires authorised finance access; auditors are read only'; end if;
 return inst;
end $$;
revoke all on function public.unimis_payment_write_access124() from public,anon;

-- Keep posted amounts and identity immutable. Corrections issue a replacement receipt.
create or replace function public.unimis_payment_integrity124()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='DELETE' then raise exception 'Keep payment history: void a posted receipt instead of deleting it'; end if;
 if old.status='completed' and (new.amount,new.invoice_id,new.student_id,new.institution_id,new.currency_code,new.payment_reference,new.payment_method,new.payment_date,new.client_request_id,new.provider,new.provider_reference,new.received_by,new.created_at)
 is distinct from (old.amount,old.invoice_id,old.student_id,old.institution_id,old.currency_code,old.payment_reference,old.payment_method,old.payment_date,old.client_request_id,old.provider,old.provider_reference,old.received_by,old.created_at) then
 raise exception 'Posted payments cannot be overwritten: use Correct / Replace'; end if;
 if old.status='completed' and new.status='completed' and (new.voided_at,new.voided_by,new.void_reason) is distinct from (old.voided_at,old.voided_by,old.void_reason) then raise exception 'Void details can only be recorded by voiding the receipt'; end if;
 if old.status in ('reversed','refunded') and new is distinct from old then raise exception 'Voided payment history is immutable'; end if;
 if old.status='completed' and new.status<>old.status and (new.status<>'reversed' or new.voided_at is null or new.voided_by is distinct from auth.uid() or nullif(btrim(new.void_reason),'') is null) then
 raise exception 'Use the authorised void receipt action'; end if;
 if old.status='completed' and new.status='reversed' then
 perform public.unimis_payment_write_access124();
 if not exists(select 1 from public.finance_journals j where j.institution_id=old.institution_id and j.source_type='student_payment_void' and j.source_id=old.id and j.status='posted') then raise exception 'Use void receipt to reverse the payment journal'; end if;
 end if;
 return new;
end $$;
drop trigger if exists unimis_payment_integrity124 on public.student_payments;
create trigger unimis_payment_integrity124 before update or delete on public.student_payments for each row execute function public.unimis_payment_integrity124();

create or replace function public.unimis_void_student_payment124(p_payment_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare inst uuid:=public.unimis_payment_write_access124(); p public.student_payments%rowtype; i public.student_invoices%rowtype; paid numeric; bal numeric; j uuid; rev uuid; seq bigint; receipt text;
begin
 if nullif(btrim(p_reason),'') is null then raise exception 'A void reason is required'; end if;
 -- Lock invoice before payment, consistently with payment posting and corrections.
 select * into p from public.student_payments where id=p_payment_id and institution_id=inst;
 if not found then raise exception 'Payment not found'; end if;
 select * into i from public.student_invoices where id=p.invoice_id and institution_id=inst for update;
 if not found then raise exception 'Linked invoice not found'; end if;
 select * into p from public.student_payments where id=p_payment_id and institution_id=inst for update;
 if p.status='reversed' then return jsonb_build_object('ok',true,'already_voided',true); end if;
 if p.status<>'completed' or p.payment_method='waiver' then raise exception 'Only completed cash receipts can be voided here'; end if;
 if p.currency_code<>'GHS' then raise exception 'Foreign currency reversals require a currency-aware treasury workflow'; end if;
 if i.status='cancelled' then raise exception 'Resolve the cancelled invoice before voiding its receipt'; end if;
 select receipt_number into receipt from public.payment_receipts where payment_id=p.id;
 -- Require and reverse the original posting; never invent a reversal for an unposted payment.
 select id into j from public.finance_journals where institution_id=inst and source_type='student_payment' and source_id=p.id and status='posted';
 if j is null then raise exception 'Original payment journal is missing. Reconcile this legacy payment before voiding'; end if;
 if (select sum(credit) from public.finance_journal_lines where journal_id=j)<>p.amount or (select sum(debit) from public.finance_journal_lines where journal_id=j)<>p.amount then raise exception 'Original journal amount does not match payment'; end if;
 insert into public.finance_journal_sequences(institution_id,last_number) values(inst,1) on conflict(institution_id) do update set last_number=public.finance_journal_sequences.last_number+1 returning last_number into seq;
 insert into public.finance_journals(institution_id,journal_number,journal_date,reference,description,status,created_by,posted_at,source_type,source_id)
 values(inst,'JV-'||to_char(current_date,'YYYY')||'-'||lpad(seq::text,6,'0'),current_date,receipt,'VOID '||coalesce(receipt,p.payment_reference)||': '||btrim(p_reason),'posted',auth.uid(),now(),'student_payment_void',p.id) returning id into rev;
 insert into public.finance_journal_lines(institution_id,journal_id,account_id,description,debit,credit)
 select institution_id,rev,account_id,'VOID: '||btrim(p_reason),credit,debit from public.finance_journal_lines where journal_id=j;
 update public.student_payments set status='reversed',voided_at=now(),voided_by=auth.uid(),void_reason=btrim(p_reason),updated_at=now() where id=p.id;
 select coalesce(sum(amount),0) into paid from public.student_payments where institution_id=inst and invoice_id=i.id and status='completed';
 bal:=greatest(i.total_amount-paid,0);
 update public.student_invoices set amount_paid=paid,balance=bal,status=case when bal<=0 then case when i.status='waived' then 'waived' else 'paid' end when paid>0 then 'part_paid' else 'unpaid' end,updated_at=now() where id=i.id;
 return jsonb_build_object('ok',true,'receipt_number',receipt,'balance',bal);
end $$;
revoke all on function public.unimis_void_student_payment124(uuid,text) from public,anon;
grant execute on function public.unimis_void_student_payment124(uuid,text) to authenticated;
create or replace function public.unimis_record_student_payment(p_payment jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_inst uuid:=public.unimis_payment_write_access124();
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
 if v_amount is null or v_amount<>round(v_amount,2) or v_amount<=0 then raise exception 'Payment amount must be greater than zero'; end if;

 if v_method='mobile_money' and nullif(btrim(coalesce(p_payment->>'reference','')),'') is null then
   raise exception 'MoMo transaction/reference number is required';
 end if;

 -- The client keeps this key across retries even when no external reference is supplied.
 if nullif(p_payment->>'request_id','') is not null then
 select id into v_id from public.student_payments where institution_id=v_inst and client_request_id=(p_payment->>'request_id')::uuid;
 if v_id is not null then
 if not exists(select 1 from public.student_payments where id=v_id and invoice_id=v_inv.id and amount=v_amount and payment_method=v_method and status='completed') then raise exception 'Request key belongs to a different or voided payment'; end if;
 select receipt_number into v_receipt from public.payment_receipts where payment_id=v_id;
 return jsonb_build_object('ok',true,'already_posted',true,'payment_id',v_id,'receipt_number',v_receipt,'balance',v_inv.balance);
 end if;
 end if;
 if nullif(btrim(p_payment->>'reference'),'') is not null and exists(select 1 from public.student_payments where institution_id=v_inst and payment_reference=btrim(p_payment->>'reference') and status<>'completed') then raise exception 'Reference is reserved by an inactive payment; enter a new reference'; end if;
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
     if not exists(select 1 from public.student_payments where id=v_id and invoice_id=v_inv.id and amount=v_amount and payment_method=v_method and currency_code=v_inv.currency_code) then raise exception 'Reference belongs to a different payment'; end if;
     select r.receipt_number into v_receipt from public.payment_receipts r where r.payment_id=v_id;
     select i.balance into v_new_bal from public.student_payments p join public.student_invoices i on i.id=p.invoice_id where p.id=v_id;
     return jsonb_build_object('ok',true,'already_posted',true,'payment_id',v_id,'receipt_number',v_receipt,'payment_reference',v_pay_ref,'balance',v_new_bal);
   end if;
 end if;

 if v_inv.status in ('cancelled','draft','waived') then raise exception 'Select an active outstanding invoice'; end if;
 if v_inv.currency_code<>'GHS' then raise exception 'Payment journal posting currently supports GHS invoices'; end if;
 if v_amount>v_inv.balance then raise exception 'Payment cannot exceed invoice balance'; end if;
 if v_method in ('waiver','scholarship') then raise exception 'Record non-cash concessions under Adjustments / Waivers'; end if;
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
   currency_code,payment_method,provider,provider_reference,status,received_by,notes,client_request_id)
 values(
   v_inst,v_inv.student_id,v_inv.id,v_pay_ref,now(),v_amount,v_inv.currency_code,
   v_method,nullif(p_payment->>'provider',''),nullif(p_payment->>'provider_reference',''),
   'completed',auth.uid(),nullif(p_payment->>'notes',''),nullif(p_payment->>'request_id','')::uuid)
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

revoke all on function public.unimis_record_student_payment(jsonb) from public,anon;
grant execute on function public.unimis_record_student_payment(jsonb) to authenticated;
create or replace function public.unimis_correct_student_payment124(p_payment_id uuid,p_reason text,p_payment jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare inst uuid:=public.unimis_payment_write_access124(); p public.student_payments%rowtype; r jsonb;
begin
 select * into p from public.student_payments where id=p_payment_id and institution_id=inst;
 if not found then raise exception 'Payment not found'; end if;
 perform 1 from public.student_invoices where id=p.invoice_id and institution_id=inst for update;
 select * into p from public.student_payments where id=p_payment_id and institution_id=inst for update;
 if nullif(p_payment->>'request_id','') is not null and exists(select 1 from public.student_payments where institution_id=inst and replaces_payment_id=p.id and client_request_id=(p_payment->>'request_id')::uuid and status='completed') then return public.unimis_record_student_payment(p_payment)||jsonb_build_object('replaced_payment_id',p.id); end if;
 if p.status<>'completed' then raise exception 'Only an active receipt can be corrected'; end if;
 if (p_payment->>'invoice_id')::uuid is distinct from p.invoice_id then raise exception 'Replacement must use the same student invoice'; end if;
 if nullif(btrim(p_payment->>'reference'),'') is not null and exists(select 1 from public.student_payments where institution_id=inst and payment_reference=btrim(p_payment->>'reference')) then raise exception 'Use a new reference for the replacement receipt'; end if;
 perform public.unimis_void_student_payment124(p.id,'Correction: '||coalesce(p_reason,''));
 if nullif(btrim(p_reason),'') is null then raise exception 'Correction reason is required'; end if;
 r:=public.unimis_record_student_payment(p_payment);
 update public.student_payments set replaces_payment_id=p.id where id=(r->>'payment_id')::uuid;
 return r||jsonb_build_object('replaced_payment_id',p.id);
end $$;
revoke all on function public.unimis_correct_student_payment124(uuid,text,jsonb) from public,anon;
grant execute on function public.unimis_correct_student_payment124(uuid,text,jsonb) to authenticated;
create or replace function public.unimis_finance_document(p_type text,p_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid:=public.unimis_finance_institution();
begin
 if v_inst is null then raise exception 'Finance access required'; end if;
 if p_type='invoice' then
  return (select jsonb_build_object('type','invoice','invoice_number',i.invoice_number,'invoice_date',i.invoice_date,'due_date',i.due_date,'currency_code',i.currency_code,'total_amount',i.total_amount,'amount_paid',i.amount_paid,'balance',i.balance,'status',i.status,'student_number',s.student_number,'student_name',concat_ws(' ',s.first_name,s.middle_name,s.last_name),'items',coalesce((select jsonb_agg(jsonb_build_object('description',ii.description,'amount',ii.line_total) order by ii.created_at) from public.student_invoice_items ii where ii.invoice_id=i.id),'[]'::jsonb)) from public.student_invoices i join public.students s on s.id=i.student_id where i.id=p_id and i.institution_id=v_inst);
 elsif p_type='receipt' then
  return (select jsonb_build_object('type','receipt','institution_name',(select name from public.institutions where id=v_inst),'status',p.status,'void_reason',p.void_reason,'voided_at',p.voided_at,'replaces_payment_id',p.replaces_payment_id,'replaces_receipt_number',(select receipt_number from public.payment_receipts where payment_id=p.replaces_payment_id),'receipt_number',r.receipt_number,'issued_at',r.issued_at,'payment_reference',p.payment_reference,'payment_date',p.payment_date,'amount',p.amount,'currency_code',p.currency_code,'payment_method',p.payment_method,'student_number',s.student_number,'student_name',concat_ws(' ',s.first_name,s.middle_name,s.last_name),'invoice_number',i.invoice_number,'invoice_balance',i.balance) from public.payment_receipts r join public.student_payments p on p.id=r.payment_id join public.students s on s.id=p.student_id left join public.student_invoices i on i.id=p.invoice_id where p.id=p_id and p.institution_id=v_inst);
 end if;
 raise exception 'Unsupported finance document';
end $$;
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
  from public.student_payments p left join public.payment_receipts r on r.payment_id=p.id and r.institution_id=p.institution_id where p.student_id=p_student_id and p.institution_id=v_inst and p.status='completed'
 )x;
 return jsonb_build_object('student',v_student,'summary',jsonb_build_object(
   'billed',coalesce((select sum(total_amount) from public.student_invoices where student_id=p_student_id and institution_id=v_inst and status<>'cancelled'),0),
   'paid',coalesce((select sum(amount) from public.student_payments where student_id=p_student_id and institution_id=v_inst and status='completed'),0),
   'outstanding',coalesce((select sum(balance) from public.student_invoices where student_id=p_student_id and institution_id=v_inst and status<>'cancelled'),0)
 ),'invoices',v_invoices,'payments',v_payments,'ledger',v_ledger);
end $$;


create or replace function public.unimis_receipt_integrity124()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='DELETE' then raise exception 'Receipts must be retained: void the linked payment'; end if;
 if (new.payment_id,new.institution_id,new.receipt_number,new.issued_at,new.issued_by) is distinct from (old.payment_id,old.institution_id,old.receipt_number,old.issued_at,old.issued_by) then raise exception 'Issued receipt identity cannot be edited'; end if;
 return new;
end $$;
drop trigger if exists unimis_receipt_integrity124 on public.payment_receipts;
create trigger unimis_receipt_integrity124 before update or delete on public.payment_receipts for each row execute function public.unimis_receipt_integrity124();

-- Application fee cash is recognised once verification succeeds, whether or not submission is complete.
-- A distinct income account makes it visible in existing GL-based financial statements.
create or replace function public.unimis_post_application_fee124(p_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare p public.admission_application_payments%rowtype; j uuid; seq bigint; cash uuid; income uuid; dt date;
begin
 select * into p from public.admission_application_payments where id=p_id for update;
 if not found or p.currency<>'GHS' then return; end if;
 if not exists(select 1 from public.applications where id=p.application_id and institution_id=p.institution_id) then raise exception 'Payment application institution mismatch'; end if;
 select id into j from public.finance_journals where institution_id=p.institution_id and source_type='application_fee' and source_id=p.id;
 if p.status='verified' and j is null then
 insert into public.finance_accounts(institution_id,code,name,account_type,normal_balance,is_control) values
 (p.institution_id,'1000','Cash and Bank','asset','debit',true),(p.institution_id,'4200','Application Fee Income','income','credit',false) on conflict(institution_id,code) do nothing;
 select id into cash from public.finance_accounts where institution_id=p.institution_id and code='1000' and account_type='asset';
 select id into income from public.finance_accounts where institution_id=p.institution_id and code='4200' and account_type='income';
 if cash is null or income is null then raise exception 'Application fee account codes conflict with the chart of accounts'; end if;
 dt:=coalesce(p.paid_at,p.verified_at,p.created_at)::date;
 insert into public.finance_journal_sequences(institution_id,last_number) values(p.institution_id,1) on conflict(institution_id) do update set last_number=public.finance_journal_sequences.last_number+1 returning last_number into seq;
 insert into public.finance_journals(institution_id,journal_number,journal_date,reference,description,status,created_by,posted_at,source_type,source_id)
 values(p.institution_id,'JV-'||to_char(dt,'YYYY')||'-'||lpad(seq::text,6,'0'),dt,p.provider_reference,'Verified application fee','posted',coalesce(p.verified_by,p.recorded_by),now(),'application_fee',p.id) returning id into j;
 insert into public.finance_journal_lines(institution_id,journal_id,account_id,description,debit,credit) values
 (p.institution_id,j,cash,'Application fee cash',p.amount,0),(p.institution_id,j,income,'Application Fee Income',0,p.amount);
 elsif p.status in ('refunded','cancelled') and j is not null and not exists(select 1 from public.finance_journals where institution_id=p.institution_id and source_type='application_fee_reversal' and source_id=p.id) then
 insert into public.finance_journal_sequences(institution_id,last_number) values(p.institution_id,1) on conflict(institution_id) do update set last_number=public.finance_journal_sequences.last_number+1 returning last_number into seq;
 insert into public.finance_journals(institution_id,journal_number,journal_date,reference,description,status,created_by,posted_at,source_type,source_id)
 values(p.institution_id,'JV-'||to_char(current_date,'YYYY')||'-'||lpad(seq::text,6,'0'),current_date,p.provider_reference,'Application fee reversal: '||p.status,'posted',auth.uid(),now(),'application_fee_reversal',p.id) returning id into cash;
 insert into public.finance_journal_lines(institution_id,journal_id,account_id,description,debit,credit)
 select institution_id,cash,account_id,'Application fee reversal',credit,debit from public.finance_journal_lines where journal_id=j;
 end if;
end $$;
revoke all on function public.unimis_post_application_fee124(uuid) from public,anon,authenticated;
create or replace function public.unimis_application_fee_trigger124()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='DELETE' then
 if exists(select 1 from public.finance_journals where source_type='application_fee' and source_id=old.id and institution_id=old.institution_id) then raise exception 'Posted application payments cannot be deleted'; end if;
 return old;
 end if;
 if tg_op='UPDATE' and exists(select 1 from public.finance_journals where source_type='application_fee' and source_id=old.id and institution_id=old.institution_id) then
 if (new.amount,new.currency,new.institution_id,new.application_id,new.paid_at,new.verified_at,new.provider_reference) is distinct from (old.amount,old.currency,old.institution_id,old.application_id,old.paid_at,old.verified_at,old.provider_reference) then raise exception 'Posted application payment details are immutable'; end if;
 if new.status not in ('verified','cancelled','refunded') or (old.status in ('refunded','cancelled') and new.status<>old.status) then raise exception 'Posted application payment cannot be reopened'; end if;
 end if;
 return new;
end $$;
drop trigger if exists unimis_application_fee_integrity124 on public.admission_application_payments;
create trigger unimis_application_fee_integrity124 before update or delete on public.admission_application_payments for each row execute function public.unimis_application_fee_trigger124();
create or replace function public.unimis_application_fee_post_trigger124()
returns trigger language plpgsql security definer set search_path='' as $$
begin perform public.unimis_post_application_fee124(new.id); return new; end $$;
drop trigger if exists unimis_application_fee_post124 on public.admission_application_payments;
create trigger unimis_application_fee_post124 after insert or update on public.admission_application_payments for each row execute function public.unimis_application_fee_post_trigger124();
-- Idempotent historical posting. Existing verified payments are recognised on their original payment date.
do $$declare p record; begin for p in select id from public.admission_application_payments where status='verified' loop perform public.unimis_post_application_fee124(p.id); end loop; end $$;

create or replace function public.unimis_application_revenue124(p_filters jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare inst uuid:=public.unimis_finance_institution(); dt_from date:=coalesce(nullif(p_filters->>'from','')::date,date_trunc('year',current_date)::date); dt_to date:=coalesce(nullif(p_filters->>'to','')::date,current_date); result jsonb;
begin
 if inst is null then raise exception 'Finance access required'; end if;
 if dt_from>dt_to then raise exception 'Invalid report date range'; end if;
 with cohort as (
 select a.id,a.application_number,a.status application_status,a.submitted_at,concat_ws(' ',ap.first_name,ap.middle_name,ap.last_name) applicant_name,ap.email,
 cy.name admission_cycle,ay.name academic_year,pr.code programme_code,pr.name programme_name
 from public.applications a join public.applicants ap on ap.id=a.applicant_id and ap.institution_id=inst
 join public.admission_cycles cy on cy.id=a.admission_cycle_id and cy.institution_id=inst
 left join public.academic_years ay on ay.id=cy.academic_year_id and ay.institution_id=inst
 left join lateral (select ch.programme_id from public.application_choices ch where ch.application_id=a.id and ch.institution_id=inst order by ch.choice_order,ch.id limit 1) ch on true
 left join public.programmes pr on pr.id=ch.programme_id and pr.institution_id=inst
 where a.institution_id=inst and (nullif(p_filters->>'academic_year_id','') is null or cy.academic_year_id=(p_filters->>'academic_year_id')::uuid)
 and (nullif(p_filters->>'programme_id','') is null or pr.id=(p_filters->>'programme_id')::uuid)
 and (nullif(p_filters->>'admission_cycle_id','') is null or cy.id=(p_filters->>'admission_cycle_id')::uuid)
 ), transactions as (
 select c.*,p.id payment_id,p.provider_reference,p.payment_method,p.status payment_status,p.amount,p.currency,coalesce(p.paid_at,p.verified_at,p.created_at) payment_date,
 case when p.status='verified' then p.amount else 0 end collected,
 exists(select 1 from public.finance_journals j where j.institution_id=inst and j.source_type='application_fee' and j.source_id=p.id) ledger_posted
 from cohort c join public.admission_application_payments p on p.application_id=c.id and p.institution_id=inst
 where coalesce(p.paid_at,p.verified_at,p.created_at)::date between dt_from and dt_to
 and p.currency=coalesce(nullif(p_filters->>'currency',''),'GHS')
 ), applicants as (
 select c.*,coalesce((select sum(t.collected) from transactions t where t.id=c.id),0) collected,
 (select count(*) from transactions t where t.id=c.id and t.payment_status='verified') verified_payments
 from cohort c where c.submitted_at::date between dt_from and dt_to
 ) select jsonb_build_object('transactions',coalesce((select jsonb_agg(to_jsonb(t) order by payment_date desc) from transactions t),'[]'::jsonb),
 'applicants',coalesce((select jsonb_agg(to_jsonb(a) order by application_number) from applicants a),'[]'::jsonb),
 'cycles',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name)) from public.admission_cycles where institution_id=inst),'[]'::jsonb),
 'summary',jsonb_build_object('collected',coalesce((select sum(collected) from transactions),0),'submitted_applicants',(select count(*) from applicants),
 'submitted_collected',coalesce((select sum(collected) from transactions where submitted_at is not null),0),
 'unsubmitted_collected',coalesce((select sum(collected) from transactions where submitted_at is null),0),
 'unposted',coalesce((select sum(collected) from transactions where not ledger_posted),0))) into result;
 return result;
end $$;
revoke all on function public.unimis_application_revenue124(jsonb) from public,anon;
grant execute on function public.unimis_application_revenue124(jsonb) to authenticated;
create or replace function public.unimis_finance_workspace(p_from date default null,p_to date default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid:=public.unimis_finance_institution(); v_from date:=coalesce(p_from,date_trunc('year',current_date)::date); v_to date:=coalesce(p_to,current_date);
begin
 if v_inst is null then raise exception 'Finance access required'; end if;
 return jsonb_build_object(
  'period',jsonb_build_object('from',v_from,'to',v_to),
  'summary',jsonb_build_object(
   'billed',coalesce((select sum(total_amount) from public.student_invoices where institution_id=v_inst and invoice_date between v_from and v_to and status<>'cancelled'),0),
   'collected',coalesce((select sum(amount) from public.student_payments where institution_id=v_inst and payment_date::date between v_from and v_to and status='completed' and payment_method<>'waiver'),0),
   'outstanding',coalesce((select sum(balance) from public.student_invoices where institution_id=v_inst and status not in('cancelled','waived')),0),
   'expenses',coalesce((select sum(amount) from public.finance_expenses where institution_id=v_inst and expense_date between v_from and v_to and status='posted'),0),
   'debtors',coalesce((select count(distinct student_id) from public.student_invoices where institution_id=v_inst and balance>0 and status not in('cancelled','waived')),0),
   'overdue',coalesce((select sum(balance) from public.student_invoices where institution_id=v_inst and balance>0 and due_date<current_date and status not in('cancelled','waived')),0)
  ),
  'accounts',coalesce((select jsonb_agg(to_jsonb(x) order by x.code) from (
    select id,code,name,account_type,normal_balance,is_control,status from public.finance_accounts where institution_id=v_inst
  )x),'[]'::jsonb),
  'invoices',coalesce((select jsonb_agg(to_jsonb(x) order by x.invoice_date desc) from (
    select si.id,si.invoice_number,si.invoice_date,si.due_date,si.total_amount,si.amount_paid,si.balance,si.status,si.currency_code,
    s.id student_id,s.student_number,concat_ws(' ',s.first_name,s.middle_name,s.last_name) student_name,
    ay.name academic_year,ap.name academic_period
    from public.student_invoices si join public.students s on s.id=si.student_id
    left join public.academic_years ay on ay.id=si.academic_year_id left join public.academic_periods ap on ap.id=si.academic_period_id
    where si.institution_id=v_inst and (si.invoice_date between v_from and v_to or (si.balance>0 and si.status not in ('cancelled','draft','waived')) or exists(select 1 from public.student_payments ps where ps.invoice_id=si.id and ps.institution_id=v_inst and ps.payment_date::date between v_from and v_to))
  )x),'[]'::jsonb),
  'payments',coalesce((select jsonb_agg(to_jsonb(x) order by x.payment_date desc) from (
    select sp.id,sp.invoice_id,sp.void_reason,sp.voided_at,sp.replaces_payment_id,sp.payment_reference,sp.payment_date,sp.amount,sp.currency_code,sp.payment_method,sp.status,
    s.student_number,concat_ws(' ',s.first_name,s.middle_name,s.last_name) student_name,
    pr.receipt_number
    from public.student_payments sp join public.students s on s.id=sp.student_id
    left join public.payment_receipts pr on pr.payment_id=sp.id
    where sp.institution_id=v_inst and sp.payment_date::date between v_from and v_to
  )x),'[]'::jsonb),
  'expenses',coalesce((select jsonb_agg(to_jsonb(x) order by x.expense_date desc) from (
    select e.id,e.expense_date,e.reference,e.description,e.amount,e.currency_code,e.payment_method,e.payee,e.status,c.name category
    from public.finance_expenses e left join public.finance_expense_categories c on c.id=e.category_id
    where e.institution_id=v_inst and e.expense_date between v_from and v_to
  )x),'[]'::jsonb),
  'fee_structures',coalesce((select jsonb_agg(to_jsonb(x) order by x.academic_year desc,x.name) from (
    select fs.id,fs.name,fs.currency_code,fs.level_number,fs.student_type,fs.status,ay.name academic_year,ap.name academic_period,p.code programme_code,
    coalesce((select sum(i.amount) from public.fee_structure_items i where i.fee_structure_id=fs.id),0) total
    from public.fee_structures fs join public.academic_years ay on ay.id=fs.academic_year_id
    left join public.academic_periods ap on ap.id=fs.academic_period_id left join public.programmes p on p.id=fs.programme_id
    where fs.institution_id=v_inst
  )x),'[]'::jsonb),
  'journals',coalesce((select jsonb_agg(to_jsonb(x) order by x.journal_date desc,x.journal_number desc) from (
    select j.id,j.journal_number,j.journal_date,j.reference,j.description,j.status,
    coalesce(sum(l.debit),0) total_debit,coalesce(sum(l.credit),0) total_credit
    from public.finance_journals j left join public.finance_journal_lines l on l.journal_id=j.id
    where j.institution_id=v_inst and j.journal_date between v_from and v_to
    group by j.id
  )x),'[]'::jsonb)
 );
end $$;

commit;
notify pgrst,'reload schema';
