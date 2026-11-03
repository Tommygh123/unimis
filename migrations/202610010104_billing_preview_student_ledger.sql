begin;

create or replace function public.unimis_preview_period_fee_invoices(
 p_faculty_id uuid default null,p_department_id uuid default null,p_programme_id uuid default null,p_level integer default null,p_student_type text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid:=public.unimis_finance_institution(); v_year uuid; v_period uuid; v_rows jsonb; v_summary jsonb;
begin
 if v_inst is null then raise exception 'Finance access required'; end if;
 select id into v_year from public.academic_years where institution_id=v_inst and is_current=true order by start_date desc limit 1;
 if v_year is null then raise exception 'No current academic year configured'; end if;
 select id into v_period from public.academic_periods where institution_id=v_inst and academic_year_id=v_year and is_current=true order by period_number limit 1;
 with eligible as (
  select s.id student_id,s.student_number,concat_ws(' ',s.first_name,s.middle_name,s.last_name) student_name,s.student_type,
         e.current_level,e.programme_id,p.code programme_code,p.name programme_name,p.department_id,d.faculty_id
  from public.students s join public.student_programme_enrolments e on e.student_id=s.id and e.is_primary=true and e.enrolment_status in ('admitted','active')
  join public.programmes p on p.id=e.programme_id left join public.departments d on d.id=p.department_id
  where s.institution_id=v_inst and s.status='active'
    and (p_faculty_id is null or d.faculty_id=p_faculty_id) and (p_department_id is null or p.department_id=p_department_id)
    and (p_programme_id is null or e.programme_id=p_programme_id) and (p_level is null or e.current_level=p_level)
    and (p_student_type is null or s.student_type=p_student_type)
 ), resolved as (
  select e.*, fs.id fee_structure_id,fs.name fee_structure_name,fs.currency_code,
    coalesce((select sum(i.amount) from public.fee_structure_items i where i.fee_structure_id=fs.id),0) amount,
    inv.id existing_invoice_id,inv.invoice_number
  from eligible e
  left join lateral (
   select f.* from public.fee_structures f
   where f.institution_id=v_inst and f.academic_year_id=v_year and f.status='active'
     and (f.academic_period_id is null or f.academic_period_id=v_period)
     and (f.faculty_id is null or f.faculty_id=e.faculty_id)
     and (f.department_id is null or f.department_id=e.department_id)
     and (f.programme_id is null or f.programme_id=e.programme_id)
     and (f.level_number is null or f.level_number=e.current_level)
     and (f.student_type is null or f.student_type=e.student_type)
   order by (f.programme_id is not null)::int desc,(f.department_id is not null)::int desc,(f.faculty_id is not null)::int desc,
            (f.level_number is not null)::int desc,(f.student_type is not null)::int desc,(f.academic_period_id is not null)::int desc,f.updated_at desc limit 1
  ) fs on true
  left join lateral (
   select si.id,si.invoice_number from public.student_invoices si
   where si.student_id=e.student_id and si.academic_year_id=v_year and si.academic_period_id is not distinct from v_period and si.status<>'cancelled'
   order by si.created_at desc limit 1
  ) inv on true
 )
 select coalesce(jsonb_agg(jsonb_build_object(
  'student_id',student_id,'student_number',student_number,'student_name',student_name,'programme_code',programme_code,'level',current_level,'student_type',student_type,
  'fee_structure_id',fee_structure_id,'fee_structure_name',fee_structure_name,'currency_code',coalesce(currency_code,'GHS'),'amount',amount,
  'status',case when existing_invoice_id is not null then 'already_invoiced' when fee_structure_id is null then 'no_fee_structure' else 'ready' end,
  'invoice_number',invoice_number) order by student_number),'[]'::jsonb) into v_rows from resolved;
 select jsonb_build_object(
  'matched_students',count(*),
  'ready',count(*) filter(where (x->>'status')='ready'),
  'already_invoiced',count(*) filter(where (x->>'status')='already_invoiced'),
  'no_fee_structure',count(*) filter(where (x->>'status')='no_fee_structure'),
  'expected_total',coalesce(sum(case when (x->>'status')='ready' then (x->>'amount')::numeric else 0 end),0)
 ) into v_summary from jsonb_array_elements(v_rows) x;
 return jsonb_build_object('academic_year_id',v_year,'academic_period_id',v_period,'summary',v_summary,'rows',v_rows);
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
  select p.id,p.payment_date,p.payment_reference,p.receipt_number,p.payment_method,p.amount,p.currency_code,p.status,p.invoice_id
  from public.student_payments p where p.student_id=p_student_id and p.institution_id=v_inst
 )x;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.txn_date,x.sort_no),'[]'::jsonb) into v_ledger from (
  select i.invoice_date::timestamp txn_date,1 sort_no,'invoice' txn_type,i.invoice_number reference,'Fee invoice' description,i.total_amount debit,0::numeric credit,i.currency_code
  from public.student_invoices i where i.student_id=p_student_id and i.institution_id=v_inst and i.status<>'cancelled'
  union all
  select p.payment_date,2,'payment',coalesce(p.receipt_number,p.payment_reference),'Fee payment — '||replace(p.payment_method,'_',' '),0,p.amount,p.currency_code
  from public.student_payments p where p.student_id=p_student_id and p.institution_id=v_inst and p.status='posted'
 )x;
 return jsonb_build_object('student',v_student,'summary',jsonb_build_object(
   'billed',coalesce((select sum(total_amount) from public.student_invoices where student_id=p_student_id and institution_id=v_inst and status<>'cancelled'),0),
   'paid',coalesce((select sum(amount) from public.student_payments where student_id=p_student_id and institution_id=v_inst and status='posted'),0),
   'outstanding',coalesce((select sum(balance) from public.student_invoices where student_id=p_student_id and institution_id=v_inst and status<>'cancelled'),0)
 ),'invoices',v_invoices,'payments',v_payments,'ledger',v_ledger);
end $$;

grant execute on function public.unimis_preview_period_fee_invoices(uuid,uuid,uuid,integer,text) to authenticated;
grant execute on function public.unimis_student_finance_ledger(uuid) to authenticated;

commit;
notify pgrst,'reload schema';
