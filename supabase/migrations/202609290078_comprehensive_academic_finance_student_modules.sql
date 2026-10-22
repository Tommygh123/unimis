
begin;

-- ============================================================
-- UniMIS 078: configurable grading, student profiles/search,
-- finance/accounting, expenses and procurement foundation.
-- ============================================================

-- Student profile enrichment used by quick-search/profile workspace.
alter table public.students add column if not exists photo_url text;
alter table public.students add column if not exists emergency_contact_name text;
alter table public.students add column if not exists emergency_contact_phone text;

-- ---------- CONFIGURABLE GRADING ----------
create or replace function public.unimis_grading_settings()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid;
begin
 select iu.institution_id into v_inst from public.institution_users iu
 where iu.user_id=auth.uid() and iu.status='active'
 order by iu.is_primary desc limit 1;
 if v_inst is null then raise exception 'Institution membership required'; end if;
 return jsonb_build_object(
  'schemes',coalesce((select jsonb_agg(jsonb_build_object(
    'id',gs.id,'name',gs.name,'code',gs.code,'gpa_scale',gs.gpa_scale,
    'is_default',gs.is_default,'status',gs.status,
    'bands',coalesce((select jsonb_agg(jsonb_build_object(
      'id',gb.id,'letter_grade',gb.letter_grade,'min_score',gb.min_score,
      'max_score',gb.max_score,'grade_point',gb.grade_point,
      'classification',gb.classification,'is_pass',gb.is_pass
    ) order by gb.min_score desc) from public.grade_bands gb where gb.grading_scheme_id=gs.id),'[]'::jsonb)
  ) order by gs.is_default desc,gs.name) from public.grading_schemes gs where gs.institution_id=v_inst),'[]'::jsonb)
 );
end $$;

create or replace function public.unimis_save_grading_scheme(p_scheme jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid; v_id uuid; b jsonb;
begin
 select iu.institution_id into v_inst from public.institution_users iu
 join public.roles r on r.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active' and r.code in ('owner','admin','exam_officer')
 order by iu.is_primary desc limit 1;
 if v_inst is null then raise exception 'Academic administration access required'; end if;

 if coalesce((p_scheme->>'is_default')::boolean,false) then
   update public.grading_schemes set is_default=false where institution_id=v_inst;
 end if;

 v_id=nullif(p_scheme->>'id','')::uuid;
 if v_id is null then
   insert into public.grading_schemes(institution_id,name,code,gpa_scale,is_default,status)
   values(v_inst,p_scheme->>'name',upper(p_scheme->>'code'),coalesce((p_scheme->>'gpa_scale')::numeric,4),
          coalesce((p_scheme->>'is_default')::boolean,false),'active')
   returning id into v_id;
 else
   update public.grading_schemes set name=p_scheme->>'name',code=upper(p_scheme->>'code'),
    gpa_scale=coalesce((p_scheme->>'gpa_scale')::numeric,gpa_scale),
    is_default=coalesce((p_scheme->>'is_default')::boolean,false),updated_at=now()
   where id=v_id and institution_id=v_inst;
 end if;

 delete from public.grade_bands where grading_scheme_id=v_id;
 for b in select * from jsonb_array_elements(coalesce(p_scheme->'bands','[]'::jsonb))
 loop
   insert into public.grade_bands(institution_id,grading_scheme_id,letter_grade,min_score,max_score,grade_point,classification,is_pass)
   values(v_inst,v_id,b->>'letter_grade',(b->>'min_score')::numeric,(b->>'max_score')::numeric,
          (b->>'grade_point')::numeric,nullif(b->>'classification',''),coalesce((b->>'is_pass')::boolean,true));
 end loop;
 return jsonb_build_object('ok',true,'id',v_id);
end $$;

-- ---------- STUDENT DIRECTORY / PROFILE ----------
create or replace function public.unimis_student_management_filters()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid;
begin
 select iu.institution_id into v_inst from public.institution_users iu where iu.user_id=auth.uid() and iu.status='active' order by iu.is_primary desc limit 1;
 if v_inst is null then raise exception 'Institution membership required'; end if;
 return jsonb_build_object(
  'academic_years',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'is_current',is_current) order by start_date desc) from public.academic_years where institution_id=v_inst),'[]'::jsonb),
  'faculties',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'code',code) order by name) from public.faculties where institution_id=v_inst),'[]'::jsonb),
  'departments',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'code',code,'faculty_id',faculty_id) order by name) from public.departments where institution_id=v_inst),'[]'::jsonb),
  'programmes',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'code',code,'department_id',department_id) order by name) from public.programmes where institution_id=v_inst),'[]'::jsonb)
 );
end $$;

create or replace function public.unimis_student_profile(p_student_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid; v_student jsonb;
begin
 select iu.institution_id into v_inst from public.institution_users iu where iu.user_id=auth.uid() and iu.status='active' order by iu.is_primary desc limit 1;
 if v_inst is null then raise exception 'Institution membership required'; end if;

 select to_jsonb(x) into v_student from (
   select s.id,s.student_number,s.first_name,s.middle_name,s.last_name,s.email,s.phone,s.gender,s.date_of_birth,
          s.nationality,s.address,s.city,s.region,s.status,s.student_type,s.photo_url,
          s.emergency_contact_name,s.emergency_contact_phone,
          spe.current_level,spe.enrolment_status,p.id programme_id,p.code programme_code,p.name programme_name,
          d.id department_id,d.name department_name,f.id faculty_id,f.name faculty_name
   from public.students s
   left join public.student_programme_enrolments spe on spe.student_id=s.id and spe.is_primary=true
   left join public.programmes p on p.id=spe.programme_id
   left join public.departments d on d.id=p.department_id
   left join public.faculties f on f.id=d.faculty_id
   where s.id=p_student_id and s.institution_id=v_inst limit 1
 ) x;
 if v_student is null then raise exception 'Student not found'; end if;

 return v_student || jsonb_build_object(
  'results',coalesce((select jsonb_agg(jsonb_build_object('course_code',c.code,'course_name',c.name,'score',cr.total_score,'grade',cr.letter_grade,'gp',cr.grade_point,'status',cr.result_status,'period',ap.name,'year',ay.name) order by ay.start_date,ap.period_number,c.code)
    from public.course_results cr join public.course_offerings co on co.id=cr.course_offering_id join public.courses c on c.id=co.course_id
    join public.academic_periods ap on ap.id=co.academic_period_id join public.academic_years ay on ay.id=ap.academic_year_id
    where cr.student_id=p_student_id),'[]'::jsonb),
  'finance',jsonb_build_object(
    'invoiced',coalesce((select sum(total_amount) from public.student_invoices where student_id=p_student_id and status<>'cancelled'),0),
    'paid',coalesce((select sum(amount) from public.student_payments where student_id=p_student_id and status='completed'),0),
    'balance',coalesce((select sum(balance) from public.student_invoices where student_id=p_student_id and status not in ('cancelled','waived')),0)
  )
 );
end $$;

-- ---------- FINANCE / ACCOUNTING ----------
create table if not exists public.finance_expense_categories(
 id uuid primary key default gen_random_uuid(), institution_id uuid not null references public.institutions(id) on delete cascade,
 code text not null,name text not null,status text not null default 'active' check(status in('active','inactive')),
 created_at timestamptz not null default now(),unique(institution_id,code)
);
create table if not exists public.finance_expenses(
 id uuid primary key default gen_random_uuid(),institution_id uuid not null references public.institutions(id) on delete cascade,
 category_id uuid references public.finance_expense_categories(id) on delete set null,
 expense_date date not null default current_date,reference text,description text not null,
 amount numeric(14,2) not null check(amount>0),currency_code text not null default 'GHS',
 payment_method text not null default 'cash',payee text,status text not null default 'posted' check(status in('draft','posted','void')),
 created_by uuid references auth.users(id) on delete set null,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table if not exists public.finance_ledger_entries(
 id uuid primary key default gen_random_uuid(),institution_id uuid not null references public.institutions(id) on delete cascade,
 entry_date date not null default current_date,source_type text not null,source_id uuid,reference text,description text not null,
 account_code text not null,account_name text not null,debit numeric(14,2) not null default 0,credit numeric(14,2) not null default 0,
 currency_code text not null default 'GHS',created_at timestamptz not null default now(),
 check(debit>=0 and credit>=0),check(not(debit>0 and credit>0))
);
create index if not exists idx_finance_expenses_inst_date on public.finance_expenses(institution_id,expense_date);
create index if not exists idx_finance_ledger_inst_date on public.finance_ledger_entries(institution_id,entry_date);

create or replace function public.unimis_finance_dashboard()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid;
begin
 select iu.institution_id into v_inst from public.institution_users iu join public.roles r on r.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active' and r.code in ('owner','admin','finance_officer')
 order by iu.is_primary desc limit 1;
 if v_inst is null then raise exception 'Finance access required'; end if;
 return jsonb_build_object(
  'summary',jsonb_build_object(
    'billed',coalesce((select sum(total_amount) from public.student_invoices where institution_id=v_inst and status<>'cancelled'),0),
    'collected',coalesce((select sum(amount) from public.student_payments where institution_id=v_inst and status='completed'),0),
    'outstanding',coalesce((select sum(balance) from public.student_invoices where institution_id=v_inst and status not in('cancelled','waived')),0),
    'expenses',coalesce((select sum(amount) from public.finance_expenses where institution_id=v_inst and status='posted'),0),
    'overdue_invoices',coalesce((select count(*) from public.student_invoices where institution_id=v_inst and balance>0 and due_date<current_date and status not in('cancelled','waived')),0)
  ),
  'invoices',coalesce((select jsonb_agg(to_jsonb(x) order by x.invoice_date desc) from (
    select si.id,si.invoice_number,si.invoice_date,si.due_date,si.total_amount,si.amount_paid,si.balance,si.status,si.currency_code,
           s.student_number,s.first_name,s.last_name
    from public.student_invoices si join public.students s on s.id=si.student_id where si.institution_id=v_inst limit 100
  )x),'[]'::jsonb),
  'payments',coalesce((select jsonb_agg(to_jsonb(x) order by x.payment_date desc) from (
    select sp.id,sp.payment_reference,sp.payment_date,sp.amount,sp.currency_code,sp.payment_method,sp.status,s.student_number,s.first_name,s.last_name
    from public.student_payments sp join public.students s on s.id=sp.student_id where sp.institution_id=v_inst limit 100
  )x),'[]'::jsonb),
  'expenses',coalesce((select jsonb_agg(to_jsonb(x) order by x.expense_date desc) from (
    select e.id,e.expense_date,e.reference,e.description,e.amount,e.currency_code,e.payment_method,e.payee,e.status,c.name category
    from public.finance_expenses e left join public.finance_expense_categories c on c.id=e.category_id where e.institution_id=v_inst limit 100
  )x),'[]'::jsonb),
  'fee_types',coalesce((select jsonb_agg(to_jsonb(x) order by x.name) from (select id,code,name,is_mandatory,status from public.fee_types where institution_id=v_inst)x),'[]'::jsonb),
  'fee_structures',coalesce((select jsonb_agg(to_jsonb(x) order by x.name) from (
    select fs.id,fs.name,fs.currency_code,fs.level_number,fs.status,ay.name academic_year,ap.name academic_period,p.code programme_code,
      coalesce((select sum(fsi.amount) from public.fee_structure_items fsi where fsi.fee_structure_id=fs.id),0) total
    from public.fee_structures fs join public.academic_years ay on ay.id=fs.academic_year_id
    left join public.academic_periods ap on ap.id=fs.academic_period_id left join public.programmes p on p.id=fs.programme_id
    where fs.institution_id=v_inst
  )x),'[]'::jsonb)
 );
end $$;

create or replace function public.unimis_record_expense(p_expense jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid; v_id uuid;
begin
 select iu.institution_id into v_inst from public.institution_users iu join public.roles r on r.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active' and r.code in ('owner','admin','finance_officer') order by iu.is_primary desc limit 1;
 if v_inst is null then raise exception 'Finance access required'; end if;
 insert into public.finance_expenses(institution_id,expense_date,description,amount,currency_code,payment_method,payee,reference,created_by)
 values(v_inst,coalesce((p_expense->>'expense_date')::date,current_date),p_expense->>'description',(p_expense->>'amount')::numeric,
        coalesce(nullif(p_expense->>'currency_code',''),'GHS'),coalesce(nullif(p_expense->>'payment_method',''),'cash'),
        nullif(p_expense->>'payee',''),nullif(p_expense->>'reference',''),auth.uid()) returning id into v_id;
 insert into public.finance_ledger_entries(institution_id,source_type,source_id,reference,description,account_code,account_name,debit,credit,currency_code)
 values(v_inst,'expense',v_id,p_expense->>'reference',p_expense->>'description','EXP','Operating Expenses',(p_expense->>'amount')::numeric,0,coalesce(nullif(p_expense->>'currency_code',''),'GHS'));
 return jsonb_build_object('ok',true,'id',v_id);
end $$;

create or replace function public.unimis_student_finance_statement()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_student uuid;
begin
 select id into v_student from public.students where user_id=auth.uid() limit 1;
 if v_student is null then raise exception 'Student profile not found'; end if;
 return jsonb_build_object(
  'summary',jsonb_build_object(
    'billed',coalesce((select sum(total_amount) from public.student_invoices where student_id=v_student and status<>'cancelled'),0),
    'paid',coalesce((select sum(amount) from public.student_payments where student_id=v_student and status='completed'),0),
    'balance',coalesce((select sum(balance) from public.student_invoices where student_id=v_student and status not in('cancelled','waived')),0)
  ),
  'invoices',coalesce((select jsonb_agg(to_jsonb(x) order by x.invoice_date desc) from (
    select invoice_number,invoice_date,due_date,total_amount,amount_paid,balance,status,currency_code from public.student_invoices where student_id=v_student
  )x),'[]'::jsonb),
  'payments',coalesce((select jsonb_agg(to_jsonb(x) order by x.payment_date desc) from (
    select payment_reference,payment_date,amount,currency_code,payment_method,status from public.student_payments where student_id=v_student
  )x),'[]'::jsonb)
 );
end $$;

-- ---------- PROCUREMENT / SUPPLY FOUNDATION ----------
create table if not exists public.suppliers(
 id uuid primary key default gen_random_uuid(),institution_id uuid not null references public.institutions(id) on delete cascade,
 name text not null,contact_person text,email text,phone text,address text,status text not null default 'active' check(status in('active','inactive')),
 created_at timestamptz not null default now()
);
create table if not exists public.purchase_requisitions(
 id uuid primary key default gen_random_uuid(),institution_id uuid not null references public.institutions(id) on delete cascade,
 requisition_no text not null,department_id uuid references public.departments(id) on delete set null,
 requested_by uuid references auth.users(id) on delete set null,request_date date not null default current_date,
 purpose text,status text not null default 'draft' check(status in('draft','submitted','approved','rejected','ordered','cancelled')),
 estimated_total numeric(14,2) not null default 0,created_at timestamptz not null default now(),unique(institution_id,requisition_no)
);
create table if not exists public.purchase_orders(
 id uuid primary key default gen_random_uuid(),institution_id uuid not null references public.institutions(id) on delete cascade,
 po_number text not null,supplier_id uuid references public.suppliers(id) on delete set null,requisition_id uuid references public.purchase_requisitions(id) on delete set null,
 order_date date not null default current_date,status text not null default 'draft' check(status in('draft','approved','sent','part_received','received','cancelled')),
 total_amount numeric(14,2) not null default 0,currency_code text not null default 'GHS',created_at timestamptz not null default now(),unique(institution_id,po_number)
);

grant execute on function public.unimis_grading_settings() to authenticated;
grant execute on function public.unimis_save_grading_scheme(jsonb) to authenticated;
grant execute on function public.unimis_student_management_filters() to authenticated;
grant execute on function public.unimis_student_profile(uuid) to authenticated;
grant execute on function public.unimis_finance_dashboard() to authenticated;
grant execute on function public.unimis_record_expense(jsonb) to authenticated;
grant execute on function public.unimis_student_finance_statement() to authenticated;

notify pgrst,'reload schema';
commit;
