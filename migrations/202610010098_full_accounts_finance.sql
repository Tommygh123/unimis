begin;

create table if not exists public.finance_accounts(
 id uuid primary key default gen_random_uuid(),
 institution_id uuid not null references public.institutions(id) on delete cascade,
 code text not null,name text not null,
 account_type text not null check(account_type in('asset','liability','equity','income','expense')),
 parent_id uuid references public.finance_accounts(id) on delete set null,
 normal_balance text not null check(normal_balance in('debit','credit')),
 is_control boolean not null default false,
 status text not null default 'active' check(status in('active','inactive')),
 created_at timestamptz not null default now(),
 unique(institution_id,code)
);

create table if not exists public.finance_journals(
 id uuid primary key default gen_random_uuid(),
 institution_id uuid not null references public.institutions(id) on delete cascade,
 journal_number text not null, journal_date date not null default current_date,
 reference text,description text not null,
 status text not null default 'posted' check(status in('draft','posted','reversed')),
 created_by uuid references auth.users(id) on delete set null,
 posted_at timestamptz,created_at timestamptz not null default now(),
 unique(institution_id,journal_number)
);

create table if not exists public.finance_journal_lines(
 id uuid primary key default gen_random_uuid(),
 institution_id uuid not null references public.institutions(id) on delete cascade,
 journal_id uuid not null references public.finance_journals(id) on delete cascade,
 account_id uuid not null references public.finance_accounts(id) on delete restrict,
 description text,debit numeric(14,2) not null default 0,credit numeric(14,2) not null default 0,
 created_at timestamptz not null default now(),
 check(debit>=0 and credit>=0),check((debit>0 and credit=0) or (credit>0 and debit=0))
);

create table if not exists public.finance_journal_sequences(
 institution_id uuid primary key references public.institutions(id) on delete cascade,
 last_number bigint not null default 0
);

create index if not exists idx_finance_journals_inst_date on public.finance_journals(institution_id,journal_date);
create index if not exists idx_finance_journal_lines_journal on public.finance_journal_lines(journal_id);
create index if not exists idx_finance_accounts_inst_type on public.finance_accounts(institution_id,account_type);

create or replace function public.unimis_finance_institution()
returns uuid language sql stable security definer set search_path='' as $$
 select iu.institution_id from public.institution_users iu
 join public.roles r on r.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active'
 and lower(coalesce(r.code,r.name)) in ('owner','admin','administrator','finance_officer','accountant','superadmin','super_admin')
 order by iu.is_primary desc limit 1
$$;

create or replace function public.unimis_seed_chart_of_accounts()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid:=public.unimis_finance_institution(); v_count int;
begin
 if v_inst is null then raise exception 'Finance access required'; end if;
 insert into public.finance_accounts(institution_id,code,name,account_type,normal_balance,is_control) values
 (v_inst,'1000','Cash and Bank','asset','debit',true),
 (v_inst,'1100','Student Fees Receivable','asset','debit',true),
 (v_inst,'1200','Other Receivables','asset','debit',false),
 (v_inst,'2000','Accounts Payable','liability','credit',true),
 (v_inst,'2100','Accrued Expenses','liability','credit',false),
 (v_inst,'3000','Accumulated Fund / Equity','equity','credit',true),
 (v_inst,'4000','Tuition and Student Fee Income','income','credit',true),
 (v_inst,'4100','Other Institutional Income','income','credit',false),
 (v_inst,'5000','Operating Expenses','expense','debit',true),
 (v_inst,'5100','Administrative Expenses','expense','debit',false),
 (v_inst,'5200','Academic Expenses','expense','debit',false),
 (v_inst,'5300','Utilities and Services','expense','debit',false)
 on conflict(institution_id,code) do nothing;
 select count(*) into v_count from public.finance_accounts where institution_id=v_inst;
 return jsonb_build_object('ok',true,'accounts',v_count);
end $$;

create or replace function public.unimis_finance_workspace(p_from date default null,p_to date default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid:=public.unimis_finance_institution(); v_from date:=coalesce(p_from,date_trunc('year',current_date)::date); v_to date:=coalesce(p_to,current_date);
begin
 if v_inst is null then raise exception 'Finance access required'; end if;
 return jsonb_build_object(
  'period',jsonb_build_object('from',v_from,'to',v_to),
  'summary',jsonb_build_object(
   'billed',coalesce((select sum(total_amount) from public.student_invoices where institution_id=v_inst and invoice_date between v_from and v_to and status<>'cancelled'),0),
   'collected',coalesce((select sum(amount) from public.student_payments where institution_id=v_inst and payment_date::date between v_from and v_to and status='completed'),0),
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
    where si.institution_id=v_inst and si.invoice_date between v_from and v_to limit 300
  )x),'[]'::jsonb),
  'payments',coalesce((select jsonb_agg(to_jsonb(x) order by x.payment_date desc) from (
    select sp.id,sp.payment_reference,sp.payment_date,sp.amount,sp.currency_code,sp.payment_method,sp.status,
    s.student_number,concat_ws(' ',s.first_name,s.middle_name,s.last_name) student_name,
    pr.receipt_number
    from public.student_payments sp join public.students s on s.id=sp.student_id
    left join public.payment_receipts pr on pr.payment_id=sp.id
    where sp.institution_id=v_inst and sp.payment_date::date between v_from and v_to limit 300
  )x),'[]'::jsonb),
  'expenses',coalesce((select jsonb_agg(to_jsonb(x) order by x.expense_date desc) from (
    select e.id,e.expense_date,e.reference,e.description,e.amount,e.currency_code,e.payment_method,e.payee,e.status,c.name category
    from public.finance_expenses e left join public.finance_expense_categories c on c.id=e.category_id
    where e.institution_id=v_inst and e.expense_date between v_from and v_to limit 300
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
    group by j.id limit 200
  )x),'[]'::jsonb)
 );
end $$;

create or replace function public.unimis_post_finance_journal(p_journal jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid:=public.unimis_finance_institution(); v_id uuid; v_no bigint; v_debit numeric:=0; v_credit numeric:=0; x jsonb; v_account uuid;
begin
 if v_inst is null then raise exception 'Finance access required'; end if;
 if jsonb_array_length(coalesce(p_journal->'lines','[]'::jsonb))<2 then raise exception 'A journal requires at least two lines'; end if;
 for x in select * from jsonb_array_elements(p_journal->'lines') loop
   v_debit:=v_debit+coalesce((x->>'debit')::numeric,0); v_credit:=v_credit+coalesce((x->>'credit')::numeric,0);
 end loop;
 if v_debit<=0 or abs(v_debit-v_credit)>0.005 then raise exception 'Journal is not balanced. Debits and credits must be equal.'; end if;
 insert into public.finance_journal_sequences(institution_id,last_number) values(v_inst,1)
 on conflict(institution_id) do update set last_number=public.finance_journal_sequences.last_number+1 returning last_number into v_no;
 insert into public.finance_journals(institution_id,journal_number,journal_date,reference,description,status,created_by,posted_at)
 values(v_inst,'JV-'||to_char(current_date,'YYYY')||'-'||lpad(v_no::text,6,'0'),coalesce((p_journal->>'journal_date')::date,current_date),nullif(p_journal->>'reference',''),p_journal->>'description','posted',auth.uid(),now()) returning id into v_id;
 for x in select * from jsonb_array_elements(p_journal->'lines') loop
   v_account:=(x->>'account_id')::uuid;
   if not exists(select 1 from public.finance_accounts where id=v_account and institution_id=v_inst and status='active') then raise exception 'Invalid finance account'; end if;
   insert into public.finance_journal_lines(institution_id,journal_id,account_id,description,debit,credit)
   values(v_inst,v_id,v_account,nullif(x->>'description',''),coalesce((x->>'debit')::numeric,0),coalesce((x->>'credit')::numeric,0));
 end loop;
 return jsonb_build_object('ok',true,'journal_id',v_id,'journal_number','JV-'||to_char(current_date,'YYYY')||'-'||lpad(v_no::text,6,'0'));
end $$;

create or replace function public.unimis_finance_reports(p_from date default null,p_to date default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid:=public.unimis_finance_institution(); v_from date:=coalesce(p_from,date_trunc('year',current_date)::date); v_to date:=coalesce(p_to,current_date);
begin
 if v_inst is null then raise exception 'Finance access required'; end if;
 return jsonb_build_object(
 'trial_balance',coalesce((select jsonb_agg(to_jsonb(x) order by x.code) from (
   select a.code,a.name,a.account_type,
   coalesce(sum(l.debit),0) debit,coalesce(sum(l.credit),0) credit,
   case when a.normal_balance='debit' then coalesce(sum(l.debit-l.credit),0) else coalesce(sum(l.credit-l.debit),0) end balance
   from public.finance_accounts a left join public.finance_journal_lines l on l.account_id=a.id
   left join public.finance_journals j on j.id=l.journal_id and j.status='posted' and j.journal_date between v_from and v_to
   where a.institution_id=v_inst group by a.id order by a.code
 )x),'[]'::jsonb),
 'income_statement',jsonb_build_object(
   'fee_income',coalesce((select sum(amount) from public.student_payments where institution_id=v_inst and status='completed' and payment_date::date between v_from and v_to),0),
   'other_income',coalesce((select sum(l.credit-l.debit) from public.finance_journal_lines l join public.finance_journals j on j.id=l.journal_id join public.finance_accounts a on a.id=l.account_id where j.institution_id=v_inst and j.status='posted' and j.journal_date between v_from and v_to and a.account_type='income'),0),
   'operating_expenses',coalesce((select sum(amount) from public.finance_expenses where institution_id=v_inst and status='posted' and expense_date between v_from and v_to),0),
   'journal_expenses',coalesce((select sum(l.debit-l.credit) from public.finance_journal_lines l join public.finance_journals j on j.id=l.journal_id join public.finance_accounts a on a.id=l.account_id where j.institution_id=v_inst and j.status='posted' and j.journal_date between v_from and v_to and a.account_type='expense'),0)
 ),
 'debtors',coalesce((select jsonb_agg(to_jsonb(x) order by x.balance desc) from (
   select s.student_number,concat_ws(' ',s.first_name,s.middle_name,s.last_name) student_name,count(si.id) invoices,sum(si.total_amount) billed,sum(si.amount_paid) paid,sum(si.balance) balance,min(si.due_date) oldest_due
   from public.student_invoices si join public.students s on s.id=si.student_id where si.institution_id=v_inst and si.balance>0 and si.status not in('cancelled','waived')
   group by s.id,s.student_number,s.first_name,s.middle_name,s.last_name
 )x),'[]'::jsonb),
 'cashbook',coalesce((select jsonb_agg(to_jsonb(x) order by x.entry_date desc) from (
   select sp.payment_date::date entry_date,sp.payment_reference reference,'Student payment' description,sp.payment_method,sp.amount receipt,0::numeric payment
   from public.student_payments sp where sp.institution_id=v_inst and sp.status='completed' and sp.payment_date::date between v_from and v_to
   union all
   select e.expense_date,e.reference,e.description,e.payment_method,0::numeric,e.amount from public.finance_expenses e where e.institution_id=v_inst and e.status='posted' and e.expense_date between v_from and v_to
 )x),'[]'::jsonb),
 'balance_sheet',jsonb_build_object(
   'cash_collected',coalesce((select sum(amount) from public.student_payments where institution_id=v_inst and status='completed'),0)-coalesce((select sum(amount) from public.finance_expenses where institution_id=v_inst and status='posted'),0),
   'student_receivables',coalesce((select sum(balance) from public.student_invoices where institution_id=v_inst and status not in('cancelled','waived')),0),
   'journal_assets',coalesce((select sum(l.debit-l.credit) from public.finance_journal_lines l join public.finance_journals j on j.id=l.journal_id join public.finance_accounts a on a.id=l.account_id where j.institution_id=v_inst and j.status='posted' and j.journal_date<=v_to and a.account_type='asset'),0),
   'liabilities',coalesce((select sum(l.credit-l.debit) from public.finance_journal_lines l join public.finance_journals j on j.id=l.journal_id join public.finance_accounts a on a.id=l.account_id where j.institution_id=v_inst and j.status='posted' and j.journal_date<=v_to and a.account_type='liability'),0),
   'equity',coalesce((select sum(l.credit-l.debit) from public.finance_journal_lines l join public.finance_journals j on j.id=l.journal_id join public.finance_accounts a on a.id=l.account_id where j.institution_id=v_inst and j.status='posted' and j.journal_date<=v_to and a.account_type='equity'),0)
 ));
end $$;

grant execute on function public.unimis_finance_institution() to authenticated;
grant execute on function public.unimis_seed_chart_of_accounts() to authenticated;
grant execute on function public.unimis_finance_workspace(date,date) to authenticated;
grant execute on function public.unimis_post_finance_journal(jsonb) to authenticated;
grant execute on function public.unimis_finance_reports(date,date) to authenticated;
commit;
notify pgrst,'reload schema';
