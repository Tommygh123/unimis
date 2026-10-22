begin;

alter table public.finance_journals add column if not exists source_type text;
alter table public.finance_journals add column if not exists source_id uuid;
create unique index if not exists uq_finance_journal_source on public.finance_journals(institution_id,source_type,source_id) where source_id is not null;

create table if not exists public.finance_document_sequences(
 institution_id uuid not null references public.institutions(id) on delete cascade,
 document_type text not null,last_number bigint not null default 0,
 primary key(institution_id,document_type)
);

create or replace function public.unimis_finance_setup()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid:=public.unimis_finance_institution();
begin
 if v_inst is null then raise exception 'Finance access required'; end if;
 return jsonb_build_object(
 'academic_years',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'is_current',is_current) order by start_date desc) from public.academic_years where institution_id=v_inst),'[]'::jsonb),
 'periods',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'academic_year_id',academic_year_id,'is_current',is_current) order by start_date desc) from public.academic_periods where institution_id=v_inst),'[]'::jsonb),
 'programmes',coalesce((select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name) order by code) from public.programmes where institution_id=v_inst),'[]'::jsonb),
 'fee_types',coalesce((select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name,'is_mandatory',is_mandatory) order by name) from public.fee_types where institution_id=v_inst and status='active'),'[]'::jsonb),
 'students',coalesce((select jsonb_agg(to_jsonb(x) order by x.student_number) from (
   select s.id,s.student_number,concat_ws(' ',s.first_name,s.middle_name,s.last_name) name,s.student_type,e.programme_id,e.current_level,p.code programme_code
   from public.students s left join public.student_programme_enrolments e on e.student_id=s.id and e.is_primary=true left join public.programmes p on p.id=e.programme_id
   where s.institution_id=v_inst and s.status='active'
 )x),'[]'::jsonb)
 );
end $$;

create or replace function public.unimis_seed_fee_types()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid:=public.unimis_finance_institution();
begin
 if v_inst is null then raise exception 'Finance access required'; end if;
 insert into public.fee_types(institution_id,code,name,description,is_mandatory,status) values
 (v_inst,'TUITION','Tuition Fee','Academic tuition charge',true,'active'),
 (v_inst,'REG','Registration Fee','Academic registration charge',true,'active'),
 (v_inst,'EXAM','Examination Fee','Examination and assessment charge',true,'active'),
 (v_inst,'ICT','ICT Fee','ICT services and infrastructure',true,'active'),
 (v_inst,'LIB','Library Fee','Library services',true,'active'),
 (v_inst,'SRC','SRC / Student Activities','Student representative and activity charge',true,'active'),
 (v_inst,'MED','Medical / Health Fee','Student health services',false,'active'),
 (v_inst,'LAB','Laboratory / Practical Fee','Laboratory and practical charge',false,'active'),
 (v_inst,'OTHER','Other Fee','Other approved student charge',false,'active')
 on conflict(institution_id,code) do nothing;
 return jsonb_build_object('ok',true);
end $$;

create or replace function public.unimis_save_fee_structure(p_structure jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid:=public.unimis_finance_institution(); v_id uuid; x jsonb; v_type uuid;
begin
 if v_inst is null then raise exception 'Finance access required'; end if;
 if nullif(p_structure->>'academic_year_id','') is null then raise exception 'Academic year is required'; end if;
 if coalesce(jsonb_array_length(p_structure->'items'),0)=0 then raise exception 'Add at least one fee item'; end if;
 if nullif(p_structure->>'id','') is null then
  insert into public.fee_structures(institution_id,academic_year_id,academic_period_id,programme_id,level_number,student_type,name,status,currency_code)
  values(v_inst,(p_structure->>'academic_year_id')::uuid,nullif(p_structure->>'academic_period_id','')::uuid,nullif(p_structure->>'programme_id','')::uuid,nullif(p_structure->>'level_number','')::int,nullif(p_structure->>'student_type',''),p_structure->>'name',coalesce(nullif(p_structure->>'status',''),'active'),coalesce(nullif(p_structure->>'currency_code',''),'GHS')) returning id into v_id;
 else
  v_id:=(p_structure->>'id')::uuid;
  if not exists(select 1 from public.fee_structures where id=v_id and institution_id=v_inst) then raise exception 'Fee structure not found'; end if;
  update public.fee_structures set academic_year_id=(p_structure->>'academic_year_id')::uuid,academic_period_id=nullif(p_structure->>'academic_period_id','')::uuid,programme_id=nullif(p_structure->>'programme_id','')::uuid,level_number=nullif(p_structure->>'level_number','')::int,student_type=nullif(p_structure->>'student_type',''),name=p_structure->>'name',status=coalesce(nullif(p_structure->>'status',''),'active'),currency_code=coalesce(nullif(p_structure->>'currency_code',''),'GHS'),updated_at=now() where id=v_id;
  delete from public.fee_structure_items where fee_structure_id=v_id;
 end if;
 for x in select * from jsonb_array_elements(p_structure->'items') loop
  v_type=nullif(x->>'fee_type_id','')::uuid;
  if v_type is null then raise exception 'Every fee item requires a fee type'; end if;
  insert into public.fee_structure_items(institution_id,fee_structure_id,fee_type_id,amount,due_date,is_optional)
  values(v_inst,v_id,v_type,coalesce((x->>'amount')::numeric,0),nullif(x->>'due_date','')::date,coalesce((x->>'is_optional')::boolean,false));
 end loop;
 return jsonb_build_object('ok',true,'id',v_id);
end $$;

create or replace function public.unimis_fee_structure_detail(p_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid:=public.unimis_finance_institution();
begin
 if v_inst is null then raise exception 'Finance access required'; end if;
 return (select jsonb_build_object('id',fs.id,'name',fs.name,'academic_year_id',fs.academic_year_id,'academic_period_id',fs.academic_period_id,'programme_id',fs.programme_id,'level_number',fs.level_number,'student_type',fs.student_type,'currency_code',fs.currency_code,'status',fs.status,
 'items',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'fee_type_id',i.fee_type_id,'fee_type',ft.name,'amount',i.amount,'due_date',i.due_date,'is_optional',i.is_optional) order by ft.name) from public.fee_structure_items i join public.fee_types ft on ft.id=i.fee_type_id where i.fee_structure_id=fs.id),'[]'::jsonb))
 from public.fee_structures fs where fs.id=p_id and fs.institution_id=v_inst);
end $$;

create or replace function public.unimis_post_auto_journal(p_source_type text,p_source_id uuid,p_date date,p_reference text,p_description text,p_debit_code text,p_credit_code text,p_amount numeric)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_inst uuid:=public.unimis_finance_institution(); v_id uuid; v_d uuid; v_c uuid; v_no bigint;
begin
 if v_inst is null or p_amount<=0 then return null; end if;
 select id into v_id from public.finance_journals where institution_id=v_inst and source_type=p_source_type and source_id=p_source_id;
 if v_id is not null then return v_id; end if;
 perform public.unimis_seed_chart_of_accounts();
 select id into v_d from public.finance_accounts where institution_id=v_inst and code=p_debit_code;
 select id into v_c from public.finance_accounts where institution_id=v_inst and code=p_credit_code;
 insert into public.finance_journal_sequences(institution_id,last_number) values(v_inst,1) on conflict(institution_id) do update set last_number=public.finance_journal_sequences.last_number+1 returning last_number into v_no;
 insert into public.finance_journals(institution_id,journal_number,journal_date,reference,description,status,created_by,posted_at,source_type,source_id)
 values(v_inst,'JV-'||to_char(p_date,'YYYY')||'-'||lpad(v_no::text,6,'0'),p_date,p_reference,p_description,'posted',auth.uid(),now(),p_source_type,p_source_id) returning id into v_id;
 insert into public.finance_journal_lines(institution_id,journal_id,account_id,description,debit,credit) values
 (v_inst,v_id,v_d,p_description,p_amount,0),(v_inst,v_id,v_c,p_description,0,p_amount);
 return v_id;
end $$;

create or replace function public.unimis_generate_fee_invoice(p_student_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb; v_inv uuid; v_amount numeric; v_ref text;
begin
 r:=public.unimis_generate_student_initial_invoice(p_student_id);
 if coalesce((r->>'ok')::boolean,false)=false then return r; end if;
 v_inv:=(r->>'invoice_id')::uuid;
 select total_amount,invoice_number into v_amount,v_ref from public.student_invoices where id=v_inv;
 perform public.unimis_post_auto_journal('student_invoice',v_inv,current_date,v_ref,'Student fee invoice '||v_ref,'1100','4000',v_amount);
 return r;
end $$;

create or replace function public.unimis_bulk_generate_fee_invoices(p_student_ids uuid[])
returns jsonb language plpgsql security definer set search_path='' as $$
declare sid uuid; r jsonb; ok int:=0; skipped int:=0; failures jsonb:='[]'::jsonb;
begin
 foreach sid in array p_student_ids loop
  begin
   r:=public.unimis_generate_fee_invoice(sid);
   if coalesce((r->>'ok')::boolean,false) then ok:=ok+1; else skipped:=skipped+1; failures:=failures||jsonb_build_array(jsonb_build_object('student_id',sid,'message',r->>'message')); end if;
  exception when others then skipped:=skipped+1; failures:=failures||jsonb_build_array(jsonb_build_object('student_id',sid,'message',sqlerrm));
  end;
 end loop;
 return jsonb_build_object('ok',true,'generated',ok,'skipped',skipped,'details',failures);
end $$;

create or replace function public.unimis_record_student_payment(p_payment jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid:=public.unimis_finance_institution(); v_inv public.student_invoices%rowtype; v_id uuid; v_seq bigint; v_pay_ref text; v_receipt text; v_amount numeric; v_new_paid numeric; v_new_bal numeric;
begin
 if v_inst is null then raise exception 'Finance access required'; end if;
 select * into v_inv from public.student_invoices where id=(p_payment->>'invoice_id')::uuid and institution_id=v_inst for update;
 if not found then raise exception 'Invoice not found'; end if;
 v_amount:=(p_payment->>'amount')::numeric;
 if v_amount<=0 then raise exception 'Payment amount must be greater than zero'; end if;
 if v_amount>v_inv.balance then raise exception 'Payment cannot exceed invoice balance'; end if;
 insert into public.finance_document_sequences(institution_id,document_type,last_number) values(v_inst,'payment',1) on conflict(institution_id,document_type) do update set last_number=public.finance_document_sequences.last_number+1 returning last_number into v_seq;
 v_pay_ref:=coalesce(nullif(p_payment->>'reference',''),'PAY/'||to_char(current_date,'YYYY')||'/'||lpad(v_seq::text,6,'0'));
 insert into public.student_payments(institution_id,student_id,invoice_id,payment_reference,payment_date,amount,currency_code,payment_method,provider,provider_reference,status,received_by,notes)
 values(v_inst,v_inv.student_id,v_inv.id,v_pay_ref,now(),v_amount,v_inv.currency_code,coalesce(nullif(p_payment->>'payment_method',''),'cash'),nullif(p_payment->>'provider',''),nullif(p_payment->>'provider_reference',''),'completed',auth.uid(),nullif(p_payment->>'notes','')) returning id into v_id;
 insert into public.finance_document_sequences(institution_id,document_type,last_number) values(v_inst,'receipt',1) on conflict(institution_id,document_type) do update set last_number=public.finance_document_sequences.last_number+1 returning last_number into v_seq;
 v_receipt:='RCT/'||to_char(current_date,'YYYY')||'/'||lpad(v_seq::text,6,'0');
 insert into public.payment_receipts(institution_id,payment_id,receipt_number,issued_by) values(v_inst,v_id,v_receipt,auth.uid());
 v_new_paid=v_inv.amount_paid+v_amount; v_new_bal=greatest(v_inv.total_amount-v_new_paid,0);
 update public.student_invoices set amount_paid=v_new_paid,balance=v_new_bal,status=case when v_new_bal<=0 then 'paid' else 'part_paid' end,updated_at=now() where id=v_inv.id;
 perform public.unimis_post_auto_journal('student_payment',v_id,current_date,v_receipt,'Student payment '||v_receipt,'1000','1100',v_amount);
 return jsonb_build_object('ok',true,'payment_id',v_id,'receipt_number',v_receipt,'payment_reference',v_pay_ref,'invoice_number',v_inv.invoice_number,'amount',v_amount,'balance',v_new_bal);
end $$;

create or replace function public.unimis_post_expense_accounting(p_expense jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid:=public.unimis_finance_institution(); v_id uuid; v_amount numeric:=(p_expense->>'amount')::numeric;
begin
 if v_inst is null then raise exception 'Finance access required'; end if;
 insert into public.finance_expenses(institution_id,expense_date,reference,description,amount,currency_code,payment_method,payee,status,created_by)
 values(v_inst,coalesce(nullif(p_expense->>'expense_date','')::date,current_date),nullif(p_expense->>'reference',''),p_expense->>'description',v_amount,coalesce(nullif(p_expense->>'currency_code',''),'GHS'),coalesce(nullif(p_expense->>'payment_method',''),'cash'),nullif(p_expense->>'payee',''),'posted',auth.uid()) returning id into v_id;
 perform public.unimis_post_auto_journal('expense',v_id,coalesce(nullif(p_expense->>'expense_date','')::date,current_date),p_expense->>'reference',p_expense->>'description','5000','1000',v_amount);
 return jsonb_build_object('ok',true,'expense_id',v_id);
end $$;

create or replace function public.unimis_finance_document(p_type text,p_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid:=public.unimis_finance_institution();
begin
 if v_inst is null then raise exception 'Finance access required'; end if;
 if p_type='invoice' then
  return (select jsonb_build_object('type','invoice','invoice_number',i.invoice_number,'invoice_date',i.invoice_date,'due_date',i.due_date,'currency_code',i.currency_code,'total_amount',i.total_amount,'amount_paid',i.amount_paid,'balance',i.balance,'status',i.status,'student_number',s.student_number,'student_name',concat_ws(' ',s.first_name,s.middle_name,s.last_name),'items',coalesce((select jsonb_agg(jsonb_build_object('description',ii.description,'amount',ii.line_total) order by ii.created_at) from public.student_invoice_items ii where ii.invoice_id=i.id),'[]'::jsonb)) from public.student_invoices i join public.students s on s.id=i.student_id where i.id=p_id and i.institution_id=v_inst);
 elsif p_type='receipt' then
  return (select jsonb_build_object('type','receipt','receipt_number',r.receipt_number,'issued_at',r.issued_at,'payment_reference',p.payment_reference,'payment_date',p.payment_date,'amount',p.amount,'currency_code',p.currency_code,'payment_method',p.payment_method,'student_number',s.student_number,'student_name',concat_ws(' ',s.first_name,s.middle_name,s.last_name),'invoice_number',i.invoice_number,'invoice_balance',i.balance) from public.payment_receipts r join public.student_payments p on p.id=r.payment_id join public.students s on s.id=p.student_id left join public.student_invoices i on i.id=p.invoice_id where p.id=p_id and p.institution_id=v_inst);
 end if;
 raise exception 'Unsupported finance document';
end $$;

grant execute on function public.unimis_finance_setup() to authenticated;
grant execute on function public.unimis_seed_fee_types() to authenticated;
grant execute on function public.unimis_save_fee_structure(jsonb) to authenticated;
grant execute on function public.unimis_fee_structure_detail(uuid) to authenticated;
grant execute on function public.unimis_generate_fee_invoice(uuid) to authenticated;
grant execute on function public.unimis_bulk_generate_fee_invoices(uuid[]) to authenticated;
grant execute on function public.unimis_record_student_payment(jsonb) to authenticated;
grant execute on function public.unimis_post_expense_accounting(jsonb) to authenticated;
grant execute on function public.unimis_finance_document(text,uuid) to authenticated;

commit;
notify pgrst,'reload schema';
