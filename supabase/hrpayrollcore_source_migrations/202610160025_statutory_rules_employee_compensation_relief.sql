-- HRPayrollCore 007b: employee compensation profile, GRA relief workflow, statutory treatment and editable PAYE versions
alter table public.payroll_profiles add column if not exists worker_tax_category text not null default 'regular', add column if not exists staff_category text not null default 'senior';
alter table public.payroll_employee_reliefs add column if not exists relief_status text not null default 'draft', add column if not exists certificate_no text, add column if not exists approval_date date, add column if not exists supporting_document_path text;

-- Ghana statutory treatment remains data-driven. Values can be superseded with new effective-dated rows.
insert into public.payroll_statutory_rules(tenant_id,country_code,authority,rule_type,name,effective_from,calculation_method,configuration,active)
select null,'GH','GRA','casual_worker_tax','Casual worker tax','2026-01-01','flat_rate',jsonb_build_object('rate',5,'basis','payment'),true
where not exists(select 1 from public.payroll_statutory_rules where tenant_id is null and country_code='GH' and rule_type='casual_worker_tax' and effective_from='2026-01-01');
insert into public.payroll_statutory_rules(tenant_id,country_code,authority,rule_type,name,effective_from,calculation_method,configuration,active)
select null,'GH','GRA','temporary_worker_tax','Resident temporary worker','2026-01-01','graduated',jsonb_build_object('method','same_as_regular_employee'),true
where not exists(select 1 from public.payroll_statutory_rules where tenant_id is null and country_code='GH' and rule_type='temporary_worker_tax' and effective_from='2026-01-01');
insert into public.payroll_statutory_rules(tenant_id,country_code,authority,rule_type,name,effective_from,calculation_method,configuration,active)
select null,'GH','GRA','non_resident_tax','Non-resident employment tax','2026-01-01','flat_rate',jsonb_build_object('general_rate',25,'bonus_overtime_rate',20),true
where not exists(select 1 from public.payroll_statutory_rules where tenant_id is null and country_code='GH' and rule_type='non_resident_tax' and effective_from='2026-01-01');
insert into public.payroll_statutory_rules(tenant_id,country_code,authority,rule_type,name,effective_from,calculation_method,configuration,active)
select null,'GH','GRA','bonus_tax','Bonus tax','2026-01-01','special',jsonb_build_object('concessionary_rate',5,'annual_basic_threshold_percent',15,'excess_treatment','graduated'),true
where not exists(select 1 from public.payroll_statutory_rules where tenant_id is null and country_code='GH' and rule_type='bonus_tax' and effective_from='2026-01-01');
insert into public.payroll_statutory_rules(tenant_id,country_code,authority,rule_type,name,effective_from,calculation_method,configuration,active)
select null,'GH','GRA','overtime_tax','Qualifying junior staff overtime','2026-01-01','special',jsonb_build_object('qualifying_annual_income_limit',18000,'up_to_50_percent_basic_rate',5,'excess_rate',10,'non_resident_rate',20),true
where not exists(select 1 from public.payroll_statutory_rules where tenant_id is null and country_code='GH' and rule_type='overtime_tax' and effective_from='2026-01-01');

-- Ghana recurring allowance catalogue. Organizations may edit treatment through their component setup.
insert into public.payroll_components(tenant_id,code,name,component_type,taxable,pensionable,calculation_type,default_amount,tax_treatment,pre_tax,recurring,active)
select t.id,v.code,v.name,'earning',true,false,'fixed',0,'graduated',false,true,true from public.tenants t cross join (values
('TRANSPORT','Transport Allowance'),('ACCOM','Rent / Accommodation Allowance'),('RISK','Risk Allowance'),('NIGHT','Night Duty Allowance'),('RESP','Responsibility Allowance'),('CHILD-ALLOW','Child Education Allowance'),('HOUSEHELP','House Help Allowance'),('COOK','Cook Allowance'),('GARDEN','Garden Boy Allowance'))v(code,name)
on conflict(tenant_id,code) do nothing;

-- Payroll-ready view supports pre-payroll validation without duplicating employee master data.
create or replace view public.payroll_employee_readiness as
select e.tenant_id,e.id employee_id,e.employee_no,concat_ws(' ',e.first_name,e.last_name) employee_name,e.employment_type,
       pp.id is not null payroll_profile_exists,coalesce(c.basic_salary,0) basic_salary,pp.tax_residency,pp.worker_tax_category,pp.tax_number,pp.ssnit_number,
       case when pp.id is null then 'Missing payroll profile' when coalesce(c.basic_salary,0)<=0 then 'Missing salary' when pp.tax_residency='resident' and coalesce(pp.tax_number,'')='' then 'Missing TIN/Ghana Card' else 'Ready' end payroll_status
from public.hr_employees e left join public.payroll_profiles pp on pp.employee_id=e.id and pp.active
left join lateral(select basic_salary from public.hr_employment_contracts c where c.employee_id=e.id and c.status='active' order by c.start_date desc limit 1)c on true;

grant select on public.payroll_employee_readiness to authenticated;

-- 007b calculation: effective PAYE version + casual/temporary/resident categories + approved relief consolidation.
create or replace function public.payroll_calculate_run(p_tenant uuid,p_period uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare r uuid; rn text; rec record; re uuid; pend date; country text; pr public.payroll_pension_rules%rowtype;
 basic numeric; earn numeric; ded numeric; taxable_extra numeric; pretax numeric; gross numeric; taxable numeric; insurable numeric; emp_pen numeric; er_pen numeric; tier1 numeric; tier2 numeric;
 pf_emp numeric; pf_er numeric; relief numeric; chargeable numeric; tx numeric; net numeric; adjearn numeric; adjded numeric; adjpretax numeric; bonus_amt numeric; overtime_amt numeric; normal_adj_earn numeric; ot_tax numeric; bonus_tax numeric; bonus_concession numeric;
begin
 if not public.has_tenant_role(p_tenant,array['owner','administrator','payroll_manager','payroll_officer']) then raise exception 'Payroll access denied'; end if;
 select end_date into pend from public.payroll_periods where id=p_period and tenant_id=p_tenant; if pend is null then raise exception 'Invalid payroll period'; end if;
 select coalesce(country_code,'GH') into country from public.payroll_settings where tenant_id=p_tenant; country:=coalesce(country,'GH');
 select * into pr from public.payroll_pension_rules x where x.country_code=country and x.active and x.effective_from<=pend and (x.effective_to is null or x.effective_to>=pend) and (x.tenant_id=p_tenant or x.tenant_id is null) order by (x.tenant_id is not null) desc,x.effective_from desc limit 1;
 if country='GH' and not exists(select 1 from public.payroll_tax_bands b where b.country_code='GH' and b.active and b.effective_from<=pend and (b.effective_to is null or b.effective_to>=pend) and (b.tenant_id=p_tenant or b.tenant_id is null)) then raise exception 'No effective PAYE bands configured for payroll period end %',pend; end if;
 select id into r from public.payroll_runs where tenant_id=p_tenant and period_id=p_period;
 if r is null then rn:='RUN-'||to_char(pend,'YYYYMM')||'-'||lpad((1+(select count(*) from public.payroll_runs where tenant_id=p_tenant))::text,3,'0'); insert into public.payroll_runs(tenant_id,period_id,run_no,status,created_by) values(p_tenant,p_period,rn,'draft',auth.uid()) returning id into r;
 else if exists(select 1 from public.payroll_runs where id=r and status in ('approved','posted')) then raise exception 'Approved/posted payroll cannot be recalculated'; end if; delete from public.payroll_run_employees where run_id=r; end if;
 for rec in select e.*,pp.tax_residency,pp.worker_tax_category,pp.staff_category,pp.pension_tier1_enabled,pp.pension_tier2_enabled,pp.provident_fund_enabled,pp.provident_employee_rate,pp.provident_employer_rate from public.hr_employees e join public.payroll_profiles pp on pp.employee_id=e.id and pp.active where e.tenant_id=p_tenant and e.employment_status='active' loop
  select coalesce((select sh.new_salary from public.hr_salary_history sh where sh.employee_id=rec.id and sh.effective_from<=pend order by sh.effective_from desc,sh.created_at desc limit 1),(select c.basic_salary from public.hr_employment_contracts c where c.employee_id=rec.id and c.status='active' order by c.start_date desc limit 1),0) into basic;
  select coalesce(sum(case when pc.component_type='earning' then pec.amount else 0 end),0),coalesce(sum(case when pc.component_type='deduction' then pec.amount else 0 end),0),coalesce(sum(case when pc.component_type='earning' and pc.taxable then pec.amount else 0 end),0),coalesce(sum(case when pc.component_type='deduction' and pc.pre_tax then pec.amount else 0 end),0) into earn,ded,taxable_extra,pretax from public.payroll_employee_components pec join public.payroll_components pc on pc.id=pec.component_id where pec.employee_id=rec.id and pec.tenant_id=p_tenant and pec.effective_from<=pend and (pec.effective_to is null or pec.effective_to>=pend) and pc.code<>'BASIC';
  select coalesce(sum(case when adjustment_type in ('earning','arrears') then amount else 0 end),0),coalesce(sum(case when adjustment_type in ('deduction','loan','unpaid_absence') then amount else 0 end),0),coalesce(sum(case when adjustment_type='pre_tax_deduction' then amount else 0 end),0),coalesce(sum(case when adjustment_type='bonus' then amount else 0 end),0),coalesce(sum(case when adjustment_type='overtime' then amount else 0 end),0) into normal_adj_earn,adjded,adjpretax,bonus_amt,overtime_amt from public.payroll_adjustments where tenant_id=p_tenant and employee_id=rec.id and period_id=p_period and status='approved';
  adjearn:=normal_adj_earn+bonus_amt+overtime_amt; gross:=basic+earn+adjearn; taxable:=basic+taxable_extra+normal_adj_earn;
  insurable:=least(greatest(basic,coalesce(pr.minimum_insurable,0)),coalesce(pr.maximum_insurable,basic)); emp_pen:=case when rec.pension_tier1_enabled then round(insurable*coalesce(pr.employee_rate,0)/100,2) else 0 end; er_pen:=case when rec.pension_tier1_enabled then round(insurable*coalesce(pr.employer_rate,0)/100,2) else 0 end; tier1:=case when rec.pension_tier1_enabled then round(insurable*coalesce(pr.tier1_total_rate,0)/100,2) else 0 end; tier2:=case when rec.pension_tier2_enabled then round(insurable*coalesce(pr.tier2_total_rate,0)/100,2) else 0 end;
  pf_emp:=case when rec.provident_fund_enabled then round(basic*coalesce(rec.provident_employee_rate,0)/100,2) else 0 end; pf_er:=case when rec.provident_fund_enabled then round(basic*coalesce(rec.provident_employer_rate,0)/100,2) else 0 end;
  select coalesce(sum(case when rt.calculation_type='percent_income' then taxable*coalesce(rt.percent_rate,0)/100 else coalesce(er.approved_annual_amount,case when rt.calculation_type='per_unit_annual' then rt.annual_amount*least(er.units,coalesce(rt.max_units,er.units)) else rt.annual_amount end,0) end)/12,0) into relief from public.payroll_employee_reliefs er join public.payroll_relief_types rt on rt.id=er.relief_type_id where er.tenant_id=p_tenant and er.employee_id=rec.id and er.approved and er.relief_status='active' and er.tax_year=extract(year from pend)::int and er.effective_from<=pend and (er.effective_to is null or er.effective_to>=pend);
  chargeable:=greatest(taxable-emp_pen-least(pf_emp+pf_er,basic*coalesce(pr.provident_tax_relief_cap_rate,0)/100)-pretax-adjpretax-relief,0);
  if rec.worker_tax_category='casual' then tx:=round(gross*0.05,2); ot_tax:=0; bonus_tax:=0;
  else
   tx:=case when rec.tax_residency='non_resident' then round(chargeable*0.25,2) else public.payroll_progressive_tax(p_tenant,country,pend,chargeable) end;
   if rec.tax_residency='non_resident' then ot_tax:=round(overtime_amt*0.20,2); bonus_tax:=round(bonus_amt*0.20,2);
   else
    if rec.staff_category='junior' and basic*12<=18000 then ot_tax:=round(least(overtime_amt,basic*0.5)*0.05+greatest(overtime_amt-basic*0.5,0)*0.10,2); else taxable:=taxable+overtime_amt; tx:=public.payroll_progressive_tax(p_tenant,country,pend,greatest(chargeable+overtime_amt,0)); ot_tax:=0; end if;
    bonus_concession:=least(bonus_amt,basic*12*0.15); bonus_tax:=round(bonus_concession*0.05,2); if bonus_amt>bonus_concession then tx:=tx+(public.payroll_progressive_tax(p_tenant,country,pend,chargeable+(bonus_amt-bonus_concession))-public.payroll_progressive_tax(p_tenant,country,pend,chargeable)); end if;
   end if; tx:=round(tx+ot_tax+bonus_tax,2);
  end if;
  net:=gross-emp_pen-pf_emp-tx-ded-adjded-pretax-adjpretax;
  insert into public.payroll_run_employees(tenant_id,run_id,employee_id,employee_no,employee_name,basic_salary,other_earnings,gross_pay,employee_pension,employer_pension,tax,other_deductions,net_pay,taxable_income,chargeable_income,tier1_total,tier2_total,provident_employee,provident_employer,tax_relief,employer_cost) values(p_tenant,r,rec.id,rec.employee_no,concat_ws(' ',rec.first_name,rec.other_names,rec.last_name),basic,earn+adjearn,gross,emp_pen,er_pen,tx,ded+adjded+pretax+adjpretax,net,taxable,chargeable,tier1,tier2,pf_emp,pf_er,relief,gross+er_pen+pf_er) returning id into re;
  insert into public.payroll_run_items(tenant_id,run_employee_id,component_code,component_name,component_type,amount,taxable,pensionable) values(p_tenant,re,'BASIC','Basic Salary','earning',basic,true,true),(p_tenant,re,'SSNIT-EE','Employee SSNIT','deduction',emp_pen,false,false),(p_tenant,re,'PAYE','PAYE / employment tax','deduction',tx,false,false);
 end loop;
 update public.payroll_runs prun set status='calculated',employee_count=x.cnt,gross_total=x.gross,deduction_total=x.ded,employee_pension_total=x.ep,employer_pension_total=x.erp,tax_total=x.tax,net_total=x.net from (select count(*) cnt,coalesce(sum(gross_pay),0) gross,coalesce(sum(other_deductions),0) ded,coalesce(sum(employee_pension),0) ep,coalesce(sum(employer_pension),0) erp,coalesce(sum(tax),0) tax,coalesce(sum(net_pay),0) net from public.payroll_run_employees where run_id=r)x where prun.id=r;
 update public.payroll_periods set status='review' where id=p_period; return r;
end $$;
grant execute on function public.payroll_calculate_run(uuid,uuid) to authenticated;
