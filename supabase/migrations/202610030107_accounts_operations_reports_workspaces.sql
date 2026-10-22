begin;

create or replace function public.unimis_finance_analytics_filters()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid:=public.unimis_finance_institution();
begin
 if v_inst is null then raise exception 'Finance access required'; end if;
 return jsonb_build_object(
  'academic_years',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by start_date desc) from public.academic_years where institution_id=v_inst),'[]'::jsonb),
  'periods',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'academic_year_id',academic_year_id) order by start_date desc) from public.academic_periods where institution_id=v_inst),'[]'::jsonb),
  'programmes',coalesce((select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name) order by code) from public.programmes where institution_id=v_inst and status='active'),'[]'::jsonb),
  'fee_types',coalesce((select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name) order by name) from public.fee_types where institution_id=v_inst and status='active'),'[]'::jsonb)
 );
end $$;

create or replace function public.unimis_finance_analytics(
 p_from date default null,p_to date default null,p_academic_year_id uuid default null,p_academic_period_id uuid default null,
 p_programme_id uuid default null,p_level integer default null,p_fee_type_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid:=public.unimis_finance_institution(); v_from date:=coalesce(p_from,date_trunc('year',current_date)::date); v_to date:=coalesce(p_to,current_date);
 v_billed numeric; v_collected numeric; v_outstanding numeric; v_expenses numeric;
begin
 if v_inst is null then raise exception 'Finance access required'; end if;

 select coalesce(sum(case when p_fee_type_id is null then i.total_amount else coalesce(fi.component_total,0) end),0),
        coalesce(sum(i.amount_paid),0),coalesce(sum(i.balance),0)
 into v_billed,v_collected,v_outstanding
 from public.student_invoices i
 join public.students s on s.id=i.student_id
 left join public.student_programme_enrolments e on e.student_id=s.id and e.is_primary=true
 left join lateral (select sum(ii.line_total) component_total from public.student_invoice_items ii where ii.invoice_id=i.id and ii.fee_type_id=p_fee_type_id) fi on true
 where i.institution_id=v_inst and i.status<>'cancelled' and i.invoice_date between v_from and v_to
 and (p_academic_year_id is null or i.academic_year_id=p_academic_year_id)
 and (p_academic_period_id is null or i.academic_period_id=p_academic_period_id)
 and (p_programme_id is null or e.programme_id=p_programme_id)
 and (p_level is null or e.current_level=p_level)
 and (p_fee_type_id is null or coalesce(fi.component_total,0)>0);

 select coalesce(sum(amount),0) into v_expenses from public.finance_expenses where institution_id=v_inst and status='posted' and expense_date between v_from and v_to;

 return jsonb_build_object(
  'summary',jsonb_build_object('billed',v_billed,'collected',v_collected,'outstanding',v_outstanding,'expenses',v_expenses,'collection_rate',case when v_billed>0 then v_collected/v_billed*100 else 0 end),
  'fee_components',coalesce((select jsonb_agg(to_jsonb(x) order by x.billed desc) from (
    select ft.name fee_type,count(distinct i.student_id) students,sum(ii.line_total) billed
    from public.student_invoice_items ii join public.student_invoices i on i.id=ii.invoice_id join public.fee_types ft on ft.id=ii.fee_type_id
    join public.students s on s.id=i.student_id left join public.student_programme_enrolments e on e.student_id=s.id and e.is_primary=true
    where i.institution_id=v_inst and i.status<>'cancelled' and i.invoice_date between v_from and v_to
      and (p_academic_year_id is null or i.academic_year_id=p_academic_year_id) and (p_academic_period_id is null or i.academic_period_id=p_academic_period_id)
      and (p_programme_id is null or e.programme_id=p_programme_id) and (p_level is null or e.current_level=p_level)
      and (p_fee_type_id is null or ii.fee_type_id=p_fee_type_id)
    group by ft.id,ft.name
  )x),'[]'::jsonb),
  'collections_by_method',coalesce((select jsonb_agg(to_jsonb(x) order by x.amount desc) from (
    select p.payment_method,count(*) transactions,sum(p.amount) amount from public.student_payments p
    join public.student_invoices i on i.id=p.invoice_id join public.students s on s.id=p.student_id
    left join public.student_programme_enrolments e on e.student_id=s.id and e.is_primary=true
    where p.institution_id=v_inst and p.status='completed' and p.payment_date::date between v_from and v_to
      and (p_academic_year_id is null or i.academic_year_id=p_academic_year_id) and (p_academic_period_id is null or i.academic_period_id=p_academic_period_id)
      and (p_programme_id is null or e.programme_id=p_programme_id) and (p_level is null or e.current_level=p_level)
    group by p.payment_method
  )x),'[]'::jsonb),
  'debtors',coalesce((select jsonb_agg(to_jsonb(x) order by x.balance desc) from (
    select s.student_number,concat_ws(' ',s.first_name,s.middle_name,s.last_name) student_name,p.code programme_code,e.current_level level,
      sum(i.total_amount) billed,sum(i.amount_paid) paid,sum(i.balance) balance
    from public.student_invoices i join public.students s on s.id=i.student_id
    left join public.student_programme_enrolments e on e.student_id=s.id and e.is_primary=true left join public.programmes p on p.id=e.programme_id
    where i.institution_id=v_inst and i.status<>'cancelled' and i.balance>0 and i.invoice_date between v_from and v_to
      and (p_academic_year_id is null or i.academic_year_id=p_academic_year_id) and (p_academic_period_id is null or i.academic_period_id=p_academic_period_id)
      and (p_programme_id is null or e.programme_id=p_programme_id) and (p_level is null or e.current_level=p_level)
    group by s.id,s.student_number,s.first_name,s.middle_name,s.last_name,p.code,e.current_level
  )x),'[]'::jsonb),
  'trial_balance',(public.unimis_finance_reports(v_from,v_to)->'trial_balance'),
  'cashbook',(public.unimis_finance_reports(v_from,v_to)->'cashbook'),
  'income_statement',(public.unimis_finance_reports(v_from,v_to)->'income_statement') ||
    jsonb_build_object('net_income',
      coalesce((public.unimis_finance_reports(v_from,v_to)->'income_statement'->>'fee_income')::numeric,0)+
      coalesce((public.unimis_finance_reports(v_from,v_to)->'income_statement'->>'other_income')::numeric,0)-
      coalesce((public.unimis_finance_reports(v_from,v_to)->'income_statement'->>'operating_expenses')::numeric,0)-
      coalesce((public.unimis_finance_reports(v_from,v_to)->'income_statement'->>'journal_expenses')::numeric,0)),
  'balance_sheet',(public.unimis_finance_reports(v_from,v_to)->'balance_sheet')
 );
end $$;

grant execute on function public.unimis_finance_analytics_filters() to authenticated;
grant execute on function public.unimis_finance_analytics(date,date,uuid,uuid,uuid,integer,uuid) to authenticated;

commit;
notify pgrst,'reload schema';
