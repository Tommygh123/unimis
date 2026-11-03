-- CONTINUATION: UniMIS Build 172 HR/Payroll repair
set search_path=unimis,public;

-- SOURCE 202610160025_statutory_rules_employee_compensation_relief.sql
-- HRPayrollCore 007b: employee compensation profile, GRA relief workflow, statutory treatment and editable PAYE versions
alter table unimis.hrc_payroll_profiles add column if not exists worker_tax_category text not null default 'regular', add column if not exists staff_category text not null default 'senior';
alter table unimis.hrc_payroll_employee_reliefs add column if not exists relief_status text not null default 'draft', add column if not exists certificate_no text, add column if not exists approval_date date, add column if not exists supporting_document_path text;

-- Ghana statutory treatment remains data-driven. Values can be superseded with new effective-dated rows.
insert into unimis.hrc_payroll_statutory_rules(tenant_id,country_code,authority,rule_type,name,effective_from,calculation_method,configuration,active)
select null,'GH','GRA','casual_worker_tax','Casual worker tax','2026-01-01','flat_rate',jsonb_build_object('rate',5,'basis','payment'),true
where not exists(select 1 from unimis.hrc_payroll_statutory_rules where tenant_id is null and country_code='GH' and rule_type='casual_worker_tax' and effective_from='2026-01-01');
insert into unimis.hrc_payroll_statutory_rules(tenant_id,country_code,authority,rule_type,name,effective_from,calculation_method,configuration,active)
select null,'GH','GRA','temporary_worker_tax','Resident temporary worker','2026-01-01','graduated',jsonb_build_object('method','same_as_regular_employee'),true
where not exists(select 1 from unimis.hrc_payroll_statutory_rules where tenant_id is null and country_code='GH' and rule_type='temporary_worker_tax' and effective_from='2026-01-01');
insert into unimis.hrc_payroll_statutory_rules(tenant_id,country_code,authority,rule_type,name,effective_from,calculation_method,configuration,active)
select null,'GH','GRA','non_resident_tax','Non-resident employment tax','2026-01-01','flat_rate',jsonb_build_object('general_rate',25,'bonus_overtime_rate',20),true
where not exists(select 1 from unimis.hrc_payroll_statutory_rules where tenant_id is null and country_code='GH' and rule_type='non_resident_tax' and effective_from='2026-01-01');
insert into unimis.hrc_payroll_statutory_rules(tenant_id,country_code,authority,rule_type,name,effective_from,calculation_method,configuration,active)
select null,'GH','GRA','bonus_tax','Bonus tax','2026-01-01','special',jsonb_build_object('concessionary_rate',5,'annual_basic_threshold_percent',15,'excess_treatment','graduated'),true
where not exists(select 1 from unimis.hrc_payroll_statutory_rules where tenant_id is null and country_code='GH' and rule_type='bonus_tax' and effective_from='2026-01-01');
insert into unimis.hrc_payroll_statutory_rules(tenant_id,country_code,authority,rule_type,name,effective_from,calculation_method,configuration,active)
select null,'GH','GRA','overtime_tax','Qualifying junior staff overtime','2026-01-01','special',jsonb_build_object('qualifying_annual_income_limit',18000,'up_to_50_percent_basic_rate',5,'excess_rate',10,'non_resident_rate',20),true
where not exists(select 1 from unimis.hrc_payroll_statutory_rules where tenant_id is null and country_code='GH' and rule_type='overtime_tax' and effective_from='2026-01-01');

-- Ghana recurring allowance catalogue. Organizations may edit treatment through their component setup.
insert into unimis.hrc_payroll_components(tenant_id,code,name,component_type,taxable,pensionable,calculation_type,default_amount,tax_treatment,pre_tax,recurring,active)
select t.id,v.code,v.name,'earning',true,false,'fixed',0,'graduated',false,true,true from unimis.hrc_tenants t cross join (values
('TRANSPORT','Transport Allowance'),('ACCOM','Rent / Accommodation Allowance'),('RISK','Risk Allowance'),('NIGHT','Night Duty Allowance'),('RESP','Responsibility Allowance'),('CHILD-ALLOW','Child Education Allowance'),('HOUSEHELP','House Help Allowance'),('COOK','Cook Allowance'),('GARDEN','Garden Boy Allowance'))v(code,name)
on conflict(tenant_id,code) do nothing;

-- Payroll-ready view supports pre-payroll validation without duplicating employee master data.
create or replace view unimis.payroll_employee_readiness as
select e.tenant_id,e.id employee_id,e.employee_no,concat_ws(' ',e.first_name,e.last_name) employee_name,e.employment_type,
       pp.id is not null payroll_profile_exists,coalesce(c.basic_salary,0) basic_salary,pp.tax_residency,pp.worker_tax_category,pp.tax_number,pp.ssnit_number,
       case when pp.id is null then 'Missing payroll profile' when coalesce(c.basic_salary,0)<=0 then 'Missing salary' when pp.tax_residency='resident' and coalesce(pp.tax_number,'')='' then 'Missing TIN/Ghana Card' else 'Ready' end payroll_status
from unimis.hrc_hr_employees e left join unimis.hrc_payroll_profiles pp on pp.employee_id=e.id and pp.active
left join lateral(select basic_salary from unimis.hrc_hr_employment_contracts c where c.employee_id=e.id and c.status='active' order by c.start_date desc limit 1)c on true;

grant select on unimis.payroll_employee_readiness to authenticated;

-- 007b calculation: effective PAYE version + casual/temporary/resident categories + approved relief consolidation.
create or replace function unimis.payroll_calculate_run(p_tenant uuid,p_period uuid)
returns uuid language plpgsql security definer set search_path=unimis as $$
declare r uuid; rn text; rec record; re uuid; pend date; country text; pr unimis.hrc_payroll_pension_rules%rowtype;
 basic numeric; earn numeric; ded numeric; taxable_extra numeric; pretax numeric; gross numeric; taxable numeric; insurable numeric; emp_pen numeric; er_pen numeric; tier1 numeric; tier2 numeric;
 pf_emp numeric; pf_er numeric; relief numeric; chargeable numeric; tx numeric; net numeric; adjearn numeric; adjded numeric; adjpretax numeric; bonus_amt numeric; overtime_amt numeric; normal_adj_earn numeric; ot_tax numeric; bonus_tax numeric; bonus_concession numeric;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','payroll_manager','payroll_officer']) then raise exception 'Payroll access denied'; end if;
 select end_date into pend from unimis.hrc_payroll_periods where id=p_period and tenant_id=p_tenant; if pend is null then raise exception 'Invalid payroll period'; end if;
 select coalesce(country_code,'GH') into country from unimis.hrc_payroll_settings where tenant_id=p_tenant; country:=coalesce(country,'GH');
 select * into pr from unimis.hrc_payroll_pension_rules x where x.country_code=country and x.active and x.effective_from<=pend and (x.effective_to is null or x.effective_to>=pend) and (x.tenant_id=p_tenant or x.tenant_id is null) order by (x.tenant_id is not null) desc,x.effective_from desc limit 1;
 if country='GH' and not exists(select 1 from unimis.hrc_payroll_tax_bands b where b.country_code='GH' and b.active and b.effective_from<=pend and (b.effective_to is null or b.effective_to>=pend) and (b.tenant_id=p_tenant or b.tenant_id is null)) then raise exception 'No effective PAYE bands configured for payroll period end %',pend; end if;
 select id into r from unimis.hrc_payroll_runs where tenant_id=p_tenant and period_id=p_period;
 if r is null then rn:='RUN-'||to_char(pend,'YYYYMM')||'-'||lpad((1+(select count(*) from unimis.hrc_payroll_runs where tenant_id=p_tenant))::text,3,'0'); insert into unimis.hrc_payroll_runs(tenant_id,period_id,run_no,status,created_by) values(p_tenant,p_period,rn,'draft',auth.uid()) returning id into r;
 else if exists(select 1 from unimis.hrc_payroll_runs where id=r and status in ('approved','posted')) then raise exception 'Approved/posted payroll cannot be recalculated'; end if; delete from unimis.hrc_payroll_run_employees where run_id=r; end if;
 for rec in select e.*,pp.tax_residency,pp.worker_tax_category,pp.staff_category,pp.pension_tier1_enabled,pp.pension_tier2_enabled,pp.provident_fund_enabled,pp.provident_employee_rate,pp.provident_employer_rate from unimis.hrc_hr_employees e join unimis.hrc_payroll_profiles pp on pp.employee_id=e.id and pp.active where e.tenant_id=p_tenant and e.employment_status='active' loop
  select coalesce((select sh.new_salary from unimis.hrc_hr_salary_history sh where sh.employee_id=rec.id and sh.effective_from<=pend order by sh.effective_from desc,sh.created_at desc limit 1),(select c.basic_salary from unimis.hrc_hr_employment_contracts c where c.employee_id=rec.id and c.status='active' order by c.start_date desc limit 1),0) into basic;
  select coalesce(sum(case when pc.component_type='earning' then pec.amount else 0 end),0),coalesce(sum(case when pc.component_type='deduction' then pec.amount else 0 end),0),coalesce(sum(case when pc.component_type='earning' and pc.taxable then pec.amount else 0 end),0),coalesce(sum(case when pc.component_type='deduction' and pc.pre_tax then pec.amount else 0 end),0) into earn,ded,taxable_extra,pretax from unimis.hrc_payroll_employee_components pec join unimis.hrc_payroll_components pc on pc.id=pec.component_id where pec.employee_id=rec.id and pec.tenant_id=p_tenant and pec.effective_from<=pend and (pec.effective_to is null or pec.effective_to>=pend) and pc.code<>'BASIC';
  select coalesce(sum(case when adjustment_type in ('earning','arrears') then amount else 0 end),0),coalesce(sum(case when adjustment_type in ('deduction','loan','unpaid_absence') then amount else 0 end),0),coalesce(sum(case when adjustment_type='pre_tax_deduction' then amount else 0 end),0),coalesce(sum(case when adjustment_type='bonus' then amount else 0 end),0),coalesce(sum(case when adjustment_type='overtime' then amount else 0 end),0) into normal_adj_earn,adjded,adjpretax,bonus_amt,overtime_amt from unimis.hrc_payroll_adjustments where tenant_id=p_tenant and employee_id=rec.id and period_id=p_period and status='approved';
  adjearn:=normal_adj_earn+bonus_amt+overtime_amt; gross:=basic+earn+adjearn; taxable:=basic+taxable_extra+normal_adj_earn;
  insurable:=least(greatest(basic,coalesce(pr.minimum_insurable,0)),coalesce(pr.maximum_insurable,basic)); emp_pen:=case when rec.pension_tier1_enabled then round(insurable*coalesce(pr.employee_rate,0)/100,2) else 0 end; er_pen:=case when rec.pension_tier1_enabled then round(insurable*coalesce(pr.employer_rate,0)/100,2) else 0 end; tier1:=case when rec.pension_tier1_enabled then round(insurable*coalesce(pr.tier1_total_rate,0)/100,2) else 0 end; tier2:=case when rec.pension_tier2_enabled then round(insurable*coalesce(pr.tier2_total_rate,0)/100,2) else 0 end;
  pf_emp:=case when rec.provident_fund_enabled then round(basic*coalesce(rec.provident_employee_rate,0)/100,2) else 0 end; pf_er:=case when rec.provident_fund_enabled then round(basic*coalesce(rec.provident_employer_rate,0)/100,2) else 0 end;
  select coalesce(sum(case when rt.calculation_type='percent_income' then taxable*coalesce(rt.percent_rate,0)/100 else coalesce(er.approved_annual_amount,case when rt.calculation_type='per_unit_annual' then rt.annual_amount*least(er.units,coalesce(rt.max_units,er.units)) else rt.annual_amount end,0) end)/12,0) into relief from unimis.hrc_payroll_employee_reliefs er join unimis.hrc_payroll_relief_types rt on rt.id=er.relief_type_id where er.tenant_id=p_tenant and er.employee_id=rec.id and er.approved and er.relief_status='active' and er.tax_year=extract(year from pend)::int and er.effective_from<=pend and (er.effective_to is null or er.effective_to>=pend);
  chargeable:=greatest(taxable-emp_pen-least(pf_emp+pf_er,basic*coalesce(pr.provident_tax_relief_cap_rate,0)/100)-pretax-adjpretax-relief,0);
  if rec.worker_tax_category='casual' then tx:=round(gross*0.05,2); ot_tax:=0; bonus_tax:=0;
  else
   tx:=case when rec.tax_residency='non_resident' then round(chargeable*0.25,2) else unimis.payroll_progressive_tax(p_tenant,country,pend,chargeable) end;
   if rec.tax_residency='non_resident' then ot_tax:=round(overtime_amt*0.20,2); bonus_tax:=round(bonus_amt*0.20,2);
   else
    if rec.staff_category='junior' and basic*12<=18000 then ot_tax:=round(least(overtime_amt,basic*0.5)*0.05+greatest(overtime_amt-basic*0.5,0)*0.10,2); else taxable:=taxable+overtime_amt; tx:=unimis.payroll_progressive_tax(p_tenant,country,pend,greatest(chargeable+overtime_amt,0)); ot_tax:=0; end if;
    bonus_concession:=least(bonus_amt,basic*12*0.15); bonus_tax:=round(bonus_concession*0.05,2); if bonus_amt>bonus_concession then tx:=tx+(unimis.payroll_progressive_tax(p_tenant,country,pend,chargeable+(bonus_amt-bonus_concession))-unimis.payroll_progressive_tax(p_tenant,country,pend,chargeable)); end if;
   end if; tx:=round(tx+ot_tax+bonus_tax,2);
  end if;
  net:=gross-emp_pen-pf_emp-tx-ded-adjded-pretax-adjpretax;
  insert into unimis.hrc_payroll_run_employees(tenant_id,run_id,employee_id,employee_no,employee_name,basic_salary,other_earnings,gross_pay,employee_pension,employer_pension,tax,other_deductions,net_pay,taxable_income,chargeable_income,tier1_total,tier2_total,provident_employee,provident_employer,tax_relief,employer_cost) values(p_tenant,r,rec.id,rec.employee_no,concat_ws(' ',rec.first_name,rec.other_names,rec.last_name),basic,earn+adjearn,gross,emp_pen,er_pen,tx,ded+adjded+pretax+adjpretax,net,taxable,chargeable,tier1,tier2,pf_emp,pf_er,relief,gross+er_pen+pf_er) returning id into re;
  insert into unimis.hrc_payroll_run_items(tenant_id,run_employee_id,component_code,component_name,component_type,amount,taxable,pensionable) values(p_tenant,re,'BASIC','Basic Salary','earning',basic,true,true),(p_tenant,re,'SSNIT-EE','Employee SSNIT','deduction',emp_pen,false,false),(p_tenant,re,'PAYE','PAYE / employment tax','deduction',tx,false,false);
 end loop;
 update unimis.hrc_payroll_runs prun set status='calculated',employee_count=x.cnt,gross_total=x.gross,deduction_total=x.ded,employee_pension_total=x.ep,employer_pension_total=x.erp,tax_total=x.tax,net_total=x.net from (select count(*) cnt,coalesce(sum(gross_pay),0) gross,coalesce(sum(other_deductions),0) ded,coalesce(sum(employee_pension),0) ep,coalesce(sum(employer_pension),0) erp,coalesce(sum(tax),0) tax,coalesce(sum(net_pay),0) net from unimis.hrc_payroll_run_employees where run_id=r)x where prun.id=r;
 update unimis.hrc_payroll_periods set status='review' where id=p_period; return r;
end $$;
grant execute on function unimis.payroll_calculate_run(uuid,uuid) to authenticated;


-- SOURCE 202610160026_payroll_reporting_integrity.sql
-- HRPayrollCore 007c: compensation/report reconciliation and payroll-ready reporting view
create or replace view unimis.payroll_employee_compensation_summary
with (security_invoker=true) as
select e.tenant_id,e.id employee_id,e.employee_no,
       concat_ws(' ',e.first_name,e.other_names,e.last_name) employee_name,
       d.name department_name,
       coalesce(sal.basic_salary,0)::numeric(14,2) basic_salary,
       coalesce(pc.recurring_earnings,0)::numeric(14,2) recurring_earnings,
       coalesce(pc.recurring_deductions,0)::numeric(14,2) recurring_deductions,
       (coalesce(sal.basic_salary,0)+coalesce(pc.recurring_earnings,0))::numeric(14,2) gross_structure,
       (coalesce(sal.basic_salary,0)+coalesce(pc.taxable_earnings,0))::numeric(14,2) taxable_structure,
       coalesce(rel.approved_annual_relief,0)::numeric(14,2) approved_annual_relief,
       round(coalesce(rel.approved_annual_relief,0)/12,2)::numeric(14,2) indicative_monthly_relief,
       (pp.id is not null and coalesce(sal.basic_salary,0)>0) payroll_ready
from unimis.hrc_hr_employees e
left join unimis.hrc_departments d on d.id=e.department_id
left join unimis.hrc_payroll_profiles pp on pp.employee_id=e.id and pp.tenant_id=e.tenant_id and pp.active
left join lateral (
  select coalesce(
    (select sh.new_salary from unimis.hrc_hr_salary_history sh where sh.employee_id=e.id and sh.tenant_id=e.tenant_id and sh.effective_from<=current_date order by sh.effective_from desc,sh.created_at desc limit 1),
    (select c.basic_salary from unimis.hrc_hr_employment_contracts c where c.employee_id=e.id and c.tenant_id=e.tenant_id and c.status='active' and c.start_date<=current_date order by c.start_date desc limit 1),0) basic_salary
) sal on true
left join lateral (
  select coalesce(sum(case when c.component_type='earning' then ec.amount else 0 end),0) recurring_earnings,
         coalesce(sum(case when c.component_type='deduction' then ec.amount else 0 end),0) recurring_deductions,
         coalesce(sum(case when c.component_type='earning' and c.taxable then ec.amount else 0 end),0) taxable_earnings
  from unimis.hrc_payroll_employee_components ec join unimis.hrc_payroll_components c on c.id=ec.component_id
  where ec.tenant_id=e.tenant_id and ec.employee_id=e.id and ec.effective_from<=current_date and (ec.effective_to is null or ec.effective_to>=current_date) and c.active
) pc on true
left join lateral (
  select coalesce(sum(er.approved_annual_amount),0) approved_annual_relief
  from unimis.hrc_payroll_employee_reliefs er
  where er.tenant_id=e.tenant_id and er.employee_id=e.id and er.approved and er.relief_status='active'
    and er.tax_year=extract(year from current_date)::int and er.effective_from<=current_date and (er.effective_to is null or er.effective_to>=current_date)
) rel on true
where e.employment_status='active';

grant select on unimis.payroll_employee_compensation_summary to authenticated;

comment on view unimis.payroll_employee_compensation_summary is '007c reconciliation view: current effective salary structure and consolidated approved annual relief. Payroll run results remain immutable after posting.';


-- SOURCE 202610160027_employee_edit_payroll_onboarding.sql
-- HRPayrollCore 007d: employee edit + payroll onboarding
create or replace function unimis.hr_update_employee_master(
 p_tenant uuid,p_employee uuid,p_first_name text,p_last_name text,p_email text,p_phone text,
 p_date_of_birth date,p_gender text,p_marital_status text,p_nationality text,p_national_id text,p_address text,
 p_department uuid,p_position uuid,p_employment_type text,p_work_schedule text,p_pay_basis text,
 p_basic_salary numeric,p_salary_effective date,p_ssnit_number text,p_tax_number text,
 p_bank_name text,p_bank_branch text,p_bank_account_name text,p_bank_account_number text,
 p_payment_method text,p_momo_network text,p_momo_number text
) returns jsonb language plpgsql security definer set search_path=unimis as $$
declare old_salary numeric(14,2); result jsonb;
begin
 if not is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if not exists(select 1 from hrc_hr_employees where id=p_employee and tenant_id=p_tenant) then raise exception 'Employee not found'; end if;
 select coalesce((select sh.new_salary from hrc_hr_salary_history sh where sh.employee_id=p_employee and sh.effective_from<=coalesce(p_salary_effective,current_date) order by sh.effective_from desc,sh.created_at desc limit 1),(select c.basic_salary from hrc_hr_employment_contracts c where c.employee_id=p_employee and c.status='active' order by c.start_date desc limit 1),0) into old_salary;
 update hrc_hr_employees set first_name=p_first_name,last_name=p_last_name,email=nullif(p_email,''),phone=nullif(p_phone,''),date_of_birth=p_date_of_birth,gender=nullif(p_gender,''),marital_status=nullif(p_marital_status,''),nationality=nullif(p_nationality,''),national_id=nullif(p_national_id,''),residential_address=nullif(p_address,''),department_id=p_department,position_id=p_position,employment_type=p_employment_type,work_schedule=p_work_schedule,pay_basis=p_pay_basis where id=p_employee and tenant_id=p_tenant;
 update hrc_payroll_profiles set ssnit_number=nullif(p_ssnit_number,''),tax_number=nullif(p_tax_number,''),bank_name=nullif(p_bank_name,''),bank_branch=nullif(p_bank_branch,''),bank_account_name=nullif(p_bank_account_name,''),bank_account_number=nullif(p_bank_account_number,''),payment_method=coalesce(nullif(p_payment_method,''),'bank'),momo_network=nullif(p_momo_network,''),momo_number=nullif(p_momo_number,'') where employee_id=p_employee and tenant_id=p_tenant;
 if p_basic_salary is not null and p_basic_salary<>old_salary then
   insert into hrc_hr_salary_history(tenant_id,employee_id,old_salary,new_salary,change_type,reason,effective_from,approved_by,created_by) values(p_tenant,p_employee,old_salary,p_basic_salary,case when old_salary=0 then 'initial_salary' else 'manual_adjustment' end,'Employee Master compensation update',coalesce(p_salary_effective,current_date),auth.uid(),auth.uid());
   if coalesce(p_salary_effective,current_date)<=current_date then update hrc_hr_employment_contracts set basic_salary=p_basic_salary where tenant_id=p_tenant and employee_id=p_employee and status='active'; end if;
 end if;
 insert into hrc_hr_employment_events(tenant_id,employee_id,event_type,effective_date,title,details,created_by) values(p_tenant,p_employee,'profile_update',current_date,'Employee master updated',jsonb_build_object('department_id',p_department,'position_id',p_position,'salary_effective',p_salary_effective),auth.uid());
 result:=jsonb_build_object('ok',true,'old_salary',old_salary,'new_salary',p_basic_salary); return result;
end $$;
grant execute on function unimis.hr_update_employee_master(uuid,uuid,text,text,text,text,date,text,text,text,text,text,uuid,uuid,text,text,text,numeric,date,text,text,text,text,text,text,text,text,text) to authenticated;


-- SOURCE 202610160028_employee_edit_schema_search_fix.sql
-- Package 007d1: correct Employee Master edit mapping.
-- pay_basis belongs to hrc_hr_employment_contracts, not hrc_hr_employees.
create or replace function unimis.hr_update_employee_master(
 p_tenant uuid,p_employee uuid,p_first_name text,p_last_name text,p_email text,p_phone text,
 p_date_of_birth date,p_gender text,p_marital_status text,p_nationality text,p_national_id text,p_address text,
 p_department uuid,p_position uuid,p_employment_type text,p_work_schedule text,p_pay_basis text,
 p_basic_salary numeric,p_salary_effective date,p_ssnit_number text,p_tax_number text,
 p_bank_name text,p_bank_branch text,p_bank_account_name text,p_bank_account_number text,
 p_payment_method text,p_momo_network text,p_momo_number text
) returns jsonb language plpgsql security definer set search_path=unimis as $$
declare old_salary numeric(14,2); active_contract uuid; result jsonb;
begin
 if not is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if not exists(select 1 from hrc_hr_employees where id=p_employee and tenant_id=p_tenant) then raise exception 'Employee not found'; end if;
 if p_pay_basis not in ('monthly','weekly','daily','hourly') then raise exception 'Invalid pay basis'; end if;
 select id,basic_salary into active_contract,old_salary from hrc_hr_employment_contracts where tenant_id=p_tenant and employee_id=p_employee and status='active' order by start_date desc limit 1;
 old_salary:=coalesce((select sh.new_salary from hrc_hr_salary_history sh where sh.employee_id=p_employee and sh.effective_from<=coalesce(p_salary_effective,current_date) order by sh.effective_from desc,sh.created_at desc limit 1),old_salary,0);
 update hrc_hr_employees set first_name=p_first_name,last_name=p_last_name,email=nullif(p_email,''),phone=nullif(p_phone,''),date_of_birth=p_date_of_birth,gender=nullif(p_gender,''),marital_status=nullif(p_marital_status,''),nationality=nullif(p_nationality,''),national_id=nullif(p_national_id,''),residential_address=nullif(p_address,''),department_id=p_department,position_id=p_position,employment_type=p_employment_type,work_schedule=p_work_schedule where id=p_employee and tenant_id=p_tenant;
 if active_contract is not null then
   update hrc_hr_employment_contracts set contract_type=p_employment_type,pay_basis=p_pay_basis,pay_frequency=p_pay_basis where id=active_contract;
 end if;
 update hrc_payroll_profiles set ssnit_number=nullif(p_ssnit_number,''),tax_number=nullif(p_tax_number,''),bank_name=nullif(p_bank_name,''),bank_branch=nullif(p_bank_branch,''),bank_account_name=nullif(p_bank_account_name,''),bank_account_number=nullif(p_bank_account_number,''),payment_method=coalesce(nullif(p_payment_method,''),'bank'),momo_network=nullif(p_momo_network,''),momo_number=nullif(p_momo_number,'') where employee_id=p_employee and tenant_id=p_tenant;
 if p_basic_salary is not null and p_basic_salary<>old_salary then
   insert into hrc_hr_salary_history(tenant_id,employee_id,old_salary,new_salary,change_type,reason,effective_from,approved_by,created_by) values(p_tenant,p_employee,old_salary,p_basic_salary,case when old_salary=0 then 'initial' else 'manual' end,'Employee Master compensation update',coalesce(p_salary_effective,current_date),auth.uid(),auth.uid());
   if active_contract is not null and coalesce(p_salary_effective,current_date)<=current_date then update hrc_hr_employment_contracts set basic_salary=p_basic_salary where id=active_contract; end if;
 end if;
 insert into hrc_hr_employment_events(tenant_id,employee_id,event_type,effective_date,title,details,created_by) values(p_tenant,p_employee,'profile_update',current_date,'Employee master updated',jsonb_build_object('department_id',p_department,'position_id',p_position,'pay_basis',p_pay_basis,'salary_effective',p_salary_effective),auth.uid());
 result:=jsonb_build_object('ok',true,'old_salary',old_salary,'new_salary',p_basic_salary,'pay_basis',p_pay_basis); return result;
end $$;
grant execute on function unimis.hr_update_employee_master(uuid,uuid,text,text,text,text,date,text,text,text,text,text,uuid,uuid,text,text,text,numeric,date,text,text,text,text,text,text,text,text,text) to authenticated;


-- SOURCE 202610160029_configurable_compensation_components.sql
-- HRPayrollCore 007e: configurable compensation components and agreed deductions
alter table unimis.hrc_payroll_components
 add column if not exists employee_or_employer text not null default 'employee',
 add column if not exists requires_consent boolean not null default false,
 add column if not exists requires_approval boolean not null default false,
 add column if not exists effective_from date not null default current_date,
 add column if not exists effective_to date,
 add column if not exists description text;

do $$ begin
  if not exists(select 1 from pg_constraint where conname='payroll_components_employee_or_employer_chk') then
    alter table unimis.hrc_payroll_components add constraint payroll_components_employee_or_employer_chk check(employee_or_employer in ('employee','employer','both'));
  end if;
end $$;

-- Organization-editable agreed deductions. These are ordinary payroll components, so the existing calculation engine consumes them.
insert into unimis.hrc_payroll_components(tenant_id,code,name,component_type,taxable,pensionable,calculation_type,default_amount,tax_treatment,pre_tax,recurring,active,employee_or_employer,requires_consent,requires_approval,effective_from,description)
select t.id,v.code,v.name,'deduction',false,false,'fixed',v.amount,'post_tax',false,true,true,'employee',v.consent,true,'2026-10-01',v.description
from unimis.hrc_tenants t cross join (values
 ('WELFARE','Staff Welfare',50::numeric,true,'Agreed staff welfare contribution'),
 ('STAFF_ASSOC','Staff Association',25::numeric,true,'Agreed staff association contribution'),
 ('UNION','Union Dues',0::numeric,true,'Union or professional association dues'),
 ('CREDIT_UNION','Credit Union',0::numeric,true,'Employee credit union contribution'),
 ('STAFF_INS','Staff Insurance',0::numeric,true,'Employee agreed insurance deduction'),
 ('STAFF_BUS','Staff Transport',0::numeric,true,'Staff transport recovery')
) v(code,name,amount,consent,description)
on conflict(tenant_id,code) do update set component_type='deduction',recurring=true,active=true,employee_or_employer='employee',requires_consent=excluded.requires_consent,requires_approval=true,description=excluded.description;

-- Make common recurring earnings explicit and organization-editable.
update unimis.hrc_payroll_components set recurring=true, employee_or_employer='employee', requires_approval=true
where code in ('TRANSPORT','ACCOM','RISK','NIGHT','RESP','CHILD-ALLOW','HOUSEHELP','COOK','GARDEN') and component_type='earning';

-- Overtime and bonus are variable inputs, not recurring compensation components.
update unimis.hrc_payroll_components set recurring=false where code in ('OT','OVERTIME','BONUS');

notify pgrst, 'reload schema';


-- SOURCE 202610160030_unified_payroll_component_catalogue.sql
-- HRPayrollCore 007e2: unified payroll component catalogue
-- The old hrc_payroll_deduction_definitions table is retained only for historical compatibility.
-- New configuration is performed exclusively through hrc_payroll_components.

-- Migrate any organization-specific deductions created in the old settings form (e.g. T & T)
-- into the universal component catalogue without assigning them to any employee.
insert into unimis.hrc_payroll_components(
  tenant_id,code,name,component_type,taxable,pensionable,calculation_type,default_amount,
  tax_treatment,pre_tax,recurring,active,employee_or_employer,requires_consent,requires_approval,
  effective_from,effective_to,description
)
select d.tenant_id, upper(replace(trim(d.code),' ','_')), d.name,
       'deduction',
       false,false,d.calculation_method,d.default_value,
       case when d.pre_tax then 'pre_tax' else 'post_tax' end,d.pre_tax,d.recurring,d.active,
       d.employee_or_employer,d.requires_consent,d.requires_approval,d.effective_from,d.effective_to,d.description
from unimis.hrc_payroll_deduction_definitions d
on conflict(tenant_id,code) do update set
  name=excluded.name,
  component_type=excluded.component_type,
  calculation_type=excluded.calculation_type,
  default_amount=excluded.default_amount,
  pre_tax=excluded.pre_tax,
  recurring=excluded.recurring,
  active=excluded.active,
  employee_or_employer=excluded.employee_or_employer,
  requires_consent=excluded.requires_consent,
  requires_approval=excluded.requires_approval,
  effective_from=excluded.effective_from,
  effective_to=excluded.effective_to,
  description=coalesce(excluded.description,unimis.hrc_payroll_components.description);

-- Safety rule: a component existing/enabled in Settings never means it is assigned to all staff.
-- Employee application remains explicit in hrc_payroll_employee_components.

insert into unimis.hrc_hrpay_audit_events(tenant_id,domain,action,entity_type,entity_reference,actor_label,new_data)
select t.id,'payroll','component_catalogue_unified','hrc_payroll_settings','007E2','System',
       jsonb_build_object('package','007e2','rule','Enabled catalogue components require explicit employee assignment')
from unimis.hrc_tenants t
where not exists(select 1 from unimis.hrc_hrpay_audit_events a where a.tenant_id=t.id and a.entity_reference='007E2');

notify pgrst, 'reload schema';


-- SOURCE 202610170032_functional_payroll_setup_configs.sql
-- HRPayrollCore 008c: functional payroll setup destinations
create table if not exists unimis.hrc_payroll_setup_configs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
  section text not null,
  config jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id, section)
);
alter table unimis.hrc_payroll_setup_configs enable row level security;
drop policy if exists payroll_setup_configs_select on unimis.hrc_payroll_setup_configs;
create policy payroll_setup_configs_select on unimis.hrc_payroll_setup_configs for select using (
 exists(select 1 from unimis.hrc_tenant_memberships tm where tm.tenant_id=hrc_payroll_setup_configs.tenant_id and tm.user_id=auth.uid() and tm.status='active')
);
drop policy if exists payroll_setup_configs_write on unimis.hrc_payroll_setup_configs;
create policy payroll_setup_configs_write on unimis.hrc_payroll_setup_configs for all using (
 exists(select 1 from unimis.hrc_tenant_memberships tm where tm.tenant_id=hrc_payroll_setup_configs.tenant_id and tm.user_id=auth.uid() and tm.status='active' and tm.role in ('owner','administrator','accountant','payroll_manager','payroll_officer','finance_manager'))
) with check (
 exists(select 1 from unimis.hrc_tenant_memberships tm where tm.tenant_id=hrc_payroll_setup_configs.tenant_id and tm.user_id=auth.uid() and tm.status='active' and tm.role in ('owner','administrator','accountant','payroll_manager','payroll_officer','finance_manager'))
);
create index if not exists payroll_setup_configs_tenant_section_idx on unimis.hrc_payroll_setup_configs(tenant_id,section);


-- SOURCE 202610170033_payroll_payment_liabilities.sql
-- HRPayrollCore 008d: payroll settlement/remittance register and accounting handoff foundation
create table if not exists unimis.hrc_payroll_payment_liabilities (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 payroll_run_id uuid null references unimis.hrc_payroll_runs(id) on delete cascade,
 liability_type text not null check (liability_type in ('employee_salary','paye','ssnit','tier2','tier3','third_party','other')),
 payee_name text not null,
 payee_reference text null,
 amount numeric(14,2) not null default 0,
 amount_paid numeric(14,2) not null default 0,
 balance numeric(14,2) not null default 0,
 due_date date null,
 payment_date date null,
 payment_method text null,
 payment_reference text null,
 evidence_path text null,
 status text not null default 'unpaid' check (status in ('unpaid','part_paid','paid','reversed')),
 accounting_status text not null default 'not_posted' check (accounting_status in ('not_posted','ready','posted','reversed')),
 accounting_reference text null,
 notes text null,
 created_by uuid null references auth.users(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create unique index if not exists uq_payroll_liability_run_type_payee on unimis.hrc_payroll_payment_liabilities(payroll_run_id,liability_type,payee_name) where payroll_run_id is not null;
alter table unimis.hrc_payroll_payment_liabilities enable row level security;
drop policy if exists payroll_payment_liabilities_member on unimis.hrc_payroll_payment_liabilities;
create policy payroll_payment_liabilities_member on unimis.hrc_payroll_payment_liabilities for all to authenticated using (unimis.is_tenant_member(tenant_id)) with check (unimis.is_tenant_member(tenant_id));
comment on table unimis.hrc_payroll_payment_liabilities is 'Settlement register for salaries, PAYE, pension and third-party payroll liabilities; suitable for accounting handoff.';


-- SOURCE 202610170034_payroll_review_complete_liabilities.sql
-- HRPayrollCore 008e: complete posted-payroll liabilities for settlement/remittance.
-- Idempotent: recreates liabilities for a run only when none exist.
create or replace function unimis.payroll_generate_payment_liabilities(p_tenant uuid,p_run uuid)
returns integer language plpgsql security definer set search_path=unimis as $$
declare r record; n integer:=0; v numeric;
begin
  if not exists(select 1 from hrc_tenant_memberships m where m.tenant_id=p_tenant and m.user_id=auth.uid() and m.status='active' and m.role in ('owner','administrator','accountant','finance_manager','payroll_manager','payroll_officer')) then raise exception 'Payroll access denied'; end if;
  select pr.*,pp.end_date into r from hrc_payroll_runs pr left join hrc_payroll_periods pp on pp.id=pr.period_id where pr.id=p_run and pr.tenant_id=p_tenant;
  if not found then raise exception 'Payroll run not found'; end if;
  if r.status<>'posted' then raise exception 'Payroll must be posted before liabilities can be generated'; end if;
  if exists(select 1 from hrc_payroll_payment_liabilities where tenant_id=p_tenant and payroll_run_id=p_run) then return 0; end if;

  select coalesce(sum(net_pay),0) into v from hrc_payroll_run_employees where run_id=p_run;
  if v>0 then insert into hrc_payroll_payment_liabilities(tenant_id,payroll_run_id,liability_type,payee_name,amount,balance,status,due_date) values(p_tenant,p_run,'employee_salary','Employees / Salary Payable',v,v,'unpaid',r.end_date); n:=n+1; end if;
  select coalesce(sum(tax),0) into v from hrc_payroll_run_employees where run_id=p_run;
  if v>0 then insert into hrc_payroll_payment_liabilities(tenant_id,payroll_run_id,liability_type,payee_name,amount,balance,status,due_date) values(p_tenant,p_run,'paye','GRA / PAYE Payable',v,v,'unpaid',r.end_date); n:=n+1; end if;
  select coalesce(sum(tier1_total),0) into v from hrc_payroll_run_employees where run_id=p_run;
  if v>0 then insert into hrc_payroll_payment_liabilities(tenant_id,payroll_run_id,liability_type,payee_name,amount,balance,status,due_date) values(p_tenant,p_run,'ssnit','SSNIT / Tier 1 Payable',v,v,'unpaid',r.end_date); n:=n+1; end if;
  select coalesce(sum(tier2_total),0) into v from hrc_payroll_run_employees where run_id=p_run;
  if v>0 then insert into hrc_payroll_payment_liabilities(tenant_id,payroll_run_id,liability_type,payee_name,amount,balance,status,due_date) values(p_tenant,p_run,'tier2','Tier 2 Trustee Payable',v,v,'unpaid',r.end_date); n:=n+1; end if;
  select coalesce(sum(provident_employee),0) into v from hrc_payroll_run_employees where run_id=p_run;
  if v>0 then insert into hrc_payroll_payment_liabilities(tenant_id,payroll_run_id,liability_type,payee_name,amount,balance,status,due_date) values(p_tenant,p_run,'tier3','Tier 3 / Provident Fund Payable',v,v,'unpaid',r.end_date); n:=n+1; end if;
  select coalesce(sum(other_deductions),0) into v from hrc_payroll_run_employees where run_id=p_run;
  if v>0 then insert into hrc_payroll_payment_liabilities(tenant_id,payroll_run_id,liability_type,payee_name,amount,balance,status,due_date) values(p_tenant,p_run,'third_party','Third-party / Agreed Deductions Payable',v,v,'unpaid',r.end_date); n:=n+1; end if;
  return n;
end $$;
grant execute on function unimis.payroll_generate_payment_liabilities(uuid,uuid) to authenticated;


-- SOURCE 202610170035_reset_payroll_run_for_testing.sql
-- HRPayrollCore 008e3: safe development/test reset for a posted payroll run.
-- This is intentionally explicit and auditable. It refuses to reset any run
-- for which a payment/remittance amount has already been recorded.

create table if not exists unimis.hrc_payroll_test_reset_audit (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  payroll_run_id uuid not null,
  run_no text,
  previous_status text,
  reset_by uuid default auth.uid(),
  reset_at timestamptz not null default now(),
  note text not null default 'Reset payroll run for controlled workflow testing'
);

alter table unimis.hrc_payroll_test_reset_audit enable row level security;

drop policy if exists payroll_test_reset_audit_select on unimis.hrc_payroll_test_reset_audit;
create policy payroll_test_reset_audit_select on unimis.hrc_payroll_test_reset_audit
for select using (
  exists (select 1 from unimis.hrc_tenant_memberships tm
          where tm.tenant_id=hrc_payroll_test_reset_audit.tenant_id
            and tm.user_id=auth.uid() and tm.status='active')
);

create or replace function unimis.payroll_reset_run_for_testing(p_tenant uuid, p_run uuid)
returns jsonb
language plpgsql
security definer
set search_path=unimis
as $$
declare
  v_run unimis.hrc_payroll_runs%rowtype;
  v_paid numeric := 0;
  v_liabilities integer := 0;
begin
  if not exists (
    select 1 from unimis.hrc_tenant_memberships tm
    where tm.tenant_id=p_tenant and tm.user_id=auth.uid() and tm.status='active'
      and tm.role in ('owner','administrator','accountant','payroll_manager','payroll_officer','finance_manager')
  ) then
    raise exception 'Payroll access denied';
  end if;

  select * into v_run from unimis.hrc_payroll_runs
   where id=p_run and tenant_id=p_tenant for update;
  if not found then raise exception 'Payroll run not found'; end if;
  if v_run.status <> 'posted' then
    raise exception 'Only a posted payroll run can be reset with this testing control';
  end if;

  if to_regclass('unimis.hrc_payroll_payment_liabilities') is not null then
    execute 'select coalesce(sum(coalesce(amount_paid,0)),0) from unimis.hrc_payroll_payment_liabilities where tenant_id=$1 and payroll_run_id=$2'
      into v_paid using p_tenant,p_run;
    if v_paid > 0 then
      raise exception 'Reset blocked: this payroll has recorded payments/remittances totaling GH₵%. Reverse those payments first.', v_paid;
    end if;
    execute 'select count(*) from unimis.hrc_payroll_payment_liabilities where tenant_id=$1 and payroll_run_id=$2'
      into v_liabilities using p_tenant,p_run;
    execute 'delete from unimis.hrc_payroll_payment_liabilities where tenant_id=$1 and payroll_run_id=$2'
      using p_tenant,p_run;
  end if;

  insert into unimis.hrc_payroll_test_reset_audit(tenant_id,payroll_run_id,run_no,previous_status)
  values(p_tenant,p_run,v_run.run_no,v_run.status);

  delete from unimis.hrc_payroll_run_employees where run_id=p_run;

  update unimis.hrc_payroll_runs
     set status='draft', employee_count=0, gross_total=0, tax_total=0, net_total=0,
         employee_pension_total=0, employer_pension_total=0
   where id=p_run and tenant_id=p_tenant;

  -- Re-open the linked period when the schema uses the standard period_id column.
  update unimis.hrc_payroll_periods p set status='open'
   where p.id=v_run.period_id and p.tenant_id=p_tenant;

  return jsonb_build_object(
    'ok',true,'run_no',v_run.run_no,'status','draft',
    'cleared_liabilities',v_liabilities,
    'message','Payroll reset to Draft. Start with Calculate / Recalculate.'
  );
end;
$$;

grant execute on function unimis.payroll_reset_run_for_testing(uuid,uuid) to authenticated;


-- SOURCE 202610170036_universal_payroll_rules_foundation.sql
-- HRPayrollCore 009 - Universal Payroll Rules & Workforce Earnings Engine Foundation
-- Adds effective-dated worker payroll classification, Tier 3 participation mode,
-- earnings-source definitions, and pension-age review flags without hard-coding
-- a person's statutory treatment from age alone.

create table if not exists unimis.hrc_payroll_worker_classifications (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
  employee_id uuid not null references unimis.hrc_hr_employees(id) on delete cascade,
  employment_relationship text not null default 'regular'
    check (employment_relationship in ('regular','fixed_term','temporary','casual','part_time','intern','national_service','locum','consultant','commission_employee','other')),
  tax_treatment text not null default 'standard_paye'
    check (tax_treatment in ('standard_paye','casual_worker','temporary_worker','non_resident','contractor_wht','special','exempt')),
  pension_status text not null default 'active_contributor'
    check (pension_status in ('active_contributor','pensioner_retiree','exempt','not_applicable','legacy_special','pending_review')),
  tier3_participation text not null default 'organization_default'
    check (tier3_participation in ('organization_default','participating','not_participating')),
  pay_frequency text not null default 'monthly'
    check (pay_frequency in ('monthly','fortnightly','weekly','daily','hourly','per_shift','per_assignment')),
  effective_from date not null default current_date,
  effective_to date,
  reason text,
  evidence_reference text,
  approved boolean not null default false,
  approved_by uuid,
  approved_at timestamptz,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (effective_to is null or effective_to >= effective_from)
);

create index if not exists idx_payroll_worker_classifications_employee
  on unimis.hrc_payroll_worker_classifications(tenant_id, employee_id, effective_from desc);
create unique index if not exists uq_payroll_worker_classification_active
  on unimis.hrc_payroll_worker_classifications(tenant_id, employee_id)
  where effective_to is null;

alter table unimis.hrc_payroll_worker_classifications enable row level security;
drop policy if exists payroll_worker_classifications_member on unimis.hrc_payroll_worker_classifications;
create policy payroll_worker_classifications_member on unimis.hrc_payroll_worker_classifications
  for all using (unimis.is_tenant_member(tenant_id))
  with check (unimis.is_tenant_member(tenant_id));

-- Explicit Tier 3 mode. Existing provident_fund_enabled/rates remain for compatibility.
alter table unimis.hrc_payroll_profiles
  add column if not exists tier3_participation_mode text not null default 'organization_default';

do $$ begin
  alter table unimis.hrc_payroll_profiles
    add constraint payroll_profiles_tier3_participation_mode_chk
    check (tier3_participation_mode in ('organization_default','participating','not_participating'));
exception when duplicate_object then null; end $$;

-- Reusable source catalogue: defines WHERE a payroll amount originates.
create table if not exists unimis.hrc_payroll_earning_sources (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
  code text not null,
  name text not null,
  source_type text not null
    check (source_type in ('compensation','recurring_component','attendance','leave','roster','overtime','commission','loan','manual_period_input','arrears','external_import','api','other')),
  description text,
  requires_approval boolean not null default true,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id, code)
);

alter table unimis.hrc_payroll_earning_sources enable row level security;
drop policy if exists payroll_earning_sources_member on unimis.hrc_payroll_earning_sources;
create policy payroll_earning_sources_member on unimis.hrc_payroll_earning_sources
  for all using (unimis.is_tenant_member(tenant_id))
  with check (unimis.is_tenant_member(tenant_id));

-- Maps a configured payroll component to its normal source. No amount is created here.
create table if not exists unimis.hrc_payroll_component_sources (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
  component_id uuid not null references unimis.hrc_payroll_components(id) on delete cascade,
  earning_source_id uuid not null references unimis.hrc_payroll_earning_sources(id) on delete cascade,
  priority integer not null default 100,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(tenant_id, component_id, earning_source_id)
);

alter table unimis.hrc_payroll_component_sources enable row level security;
drop policy if exists payroll_component_sources_member on unimis.hrc_payroll_component_sources;
create policy payroll_component_sources_member on unimis.hrc_payroll_component_sources
  for all using (unimis.is_tenant_member(tenant_id))
  with check (unimis.is_tenant_member(tenant_id));

-- Configurable review milestones. A milestone raises a review flag only; it never
-- automatically stops SSNIT/Tier 2/Tier 3 or changes tax treatment.
create table if not exists unimis.hrc_payroll_pension_review_rules (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
  country_code text not null default 'GH',
  review_age integer not null default 55 check (review_age between 18 and 100),
  label text not null default 'Pension status review',
  message text not null default 'Employee has reached a configured pension milestone. Review contributor/pension status before payroll.',
  active boolean not null default true,
  effective_from date not null default current_date,
  effective_to date,
  created_at timestamptz not null default now(),
  unique(tenant_id, country_code, review_age, effective_from)
);

alter table unimis.hrc_payroll_pension_review_rules enable row level security;
drop policy if exists payroll_pension_review_rules_member on unimis.hrc_payroll_pension_review_rules;
create policy payroll_pension_review_rules_member on unimis.hrc_payroll_pension_review_rules
  for all using (unimis.is_tenant_member(tenant_id))
  with check (unimis.is_tenant_member(tenant_id));

-- Seed source definitions for every tenant. Safe to rerun.
insert into unimis.hrc_payroll_earning_sources(tenant_id,code,name,source_type,description,requires_approval)
select t.id,v.code,v.name,v.source_type,v.description,v.requires_approval
from unimis.hrc_tenants t
cross join (values
 ('COMPENSATION','Employee compensation','compensation','Basic salary/base rate from the effective compensation profile.',false),
 ('RECURRING','Recurring assignment','recurring_component','Effective-dated recurring earnings or deductions assigned to an employee.',true),
 ('ATTENDANCE','Attendance','attendance','Approved attendance-derived payable time or exception.',true),
 ('LEAVE','Leave','leave','Approved paid/unpaid leave effect.',true),
 ('ROSTER','Roster / shift','roster','Approved scheduled shift or shift premium.',true),
 ('OVERTIME','Overtime','overtime','Approved overtime quantity/value.',true),
 ('COMMISSION','Commission','commission','Approved sales/activity commission.',true),
 ('LOAN','Loan schedule','loan','Scheduled employee loan repayment.',true),
 ('PERIOD_INPUT','Manual period input','manual_period_input','One-off payroll input such as bonus or adjustment.',true),
 ('ARREARS','Arrears','arrears','Approved prior-period arrears or correction.',true),
 ('EXTERNAL','External import / API','external_import','Approved value imported from a host system or external source.',true)
) as v(code,name,source_type,description,requires_approval)
on conflict (tenant_id,code) do nothing;

-- Default Ghana review milestone for existing hrc_tenants. This is a REVIEW trigger,
-- not a statutory deduction decision.
insert into unimis.hrc_payroll_pension_review_rules(tenant_id,country_code,review_age,label,message,effective_from)
select id,'GH',55,'Pension status review','Employee has reached age 55. Review pension/contributor status; do not automatically stop statutory deductions.',current_date
from unimis.hrc_tenants
on conflict (tenant_id,country_code,review_age,effective_from) do nothing;

comment on table unimis.hrc_payroll_worker_classifications is 'Effective-dated payroll classification. Employment relationship, tax treatment and pension status are intentionally separate.';
comment on column unimis.hrc_payroll_worker_classifications.pension_status is 'Controls pension treatment; age alone must never silently change deductions.';
comment on column unimis.hrc_payroll_worker_classifications.tier3_participation is 'Organization default, explicit participation, or explicit non-participation.';
comment on table unimis.hrc_payroll_earning_sources is 'Defines the origin of payroll values so one payroll engine can consume compensation, attendance, roster, commission, loans and manual inputs.';


-- SOURCE 202610170037_payroll_classification_workspace.sql
-- HRPayrollCore 009a - Payroll Classification & Pension Status Workspace
-- Safe effective-dated classification setter and employee Tier 3 metadata.

alter table unimis.hrc_payroll_profiles
  add column if not exists provident_member_reference text,
  add column if not exists provident_effective_from date,
  add column if not exists provident_effective_to date;

insert into unimis.hrc_payroll_pension_review_rules
  (tenant_id,country_code,review_age,label,message,active,effective_from)
select t.id,'GH',55,'Pension status review',
       'Employee has reached a configured pension milestone. Review contributor/pension status before payroll. No deduction is changed automatically.',
       true,current_date
from unimis.hrc_tenants t
where not exists (
  select 1 from unimis.hrc_payroll_pension_review_rules r
  where r.tenant_id=t.id and r.country_code='GH' and r.active=true
);

create or replace function unimis.payroll_set_worker_classification(
  p_tenant uuid,
  p_employee uuid,
  p_employment_relationship text,
  p_tax_treatment text,
  p_pension_status text,
  p_tier3_participation text,
  p_pay_frequency text,
  p_effective_from date,
  p_reason text default null,
  p_evidence_reference text default null
) returns uuid
language plpgsql
security definer
set search_path=unimis
as $$
declare
  v_id uuid;
  v_existing unimis.hrc_payroll_worker_classifications%rowtype;
begin
  if not unimis.is_tenant_member(p_tenant) then
    raise exception 'Tenant access denied';
  end if;
  if not exists(select 1 from unimis.hrc_hr_employees where id=p_employee and tenant_id=p_tenant) then
    raise exception 'Employee does not belong to this tenant';
  end if;

  select * into v_existing
  from unimis.hrc_payroll_worker_classifications
  where tenant_id=p_tenant and employee_id=p_employee and effective_to is null
  order by effective_from desc limit 1;

  if v_existing.id is not null then
    if p_effective_from < v_existing.effective_from then
      raise exception 'New effective date cannot be earlier than the current classification effective date';
    elsif p_effective_from = v_existing.effective_from then
      update unimis.hrc_payroll_worker_classifications
      set employment_relationship=p_employment_relationship,
          tax_treatment=p_tax_treatment,
          pension_status=p_pension_status,
          tier3_participation=p_tier3_participation,
          pay_frequency=p_pay_frequency,
          reason=p_reason,
          evidence_reference=p_evidence_reference,
          updated_at=now()
      where id=v_existing.id
      returning id into v_id;
      return v_id;
    else
      update unimis.hrc_payroll_worker_classifications
      set effective_to=p_effective_from-1, updated_at=now()
      where id=v_existing.id;
    end if;
  end if;

  insert into unimis.hrc_payroll_worker_classifications(
    tenant_id,employee_id,employment_relationship,tax_treatment,pension_status,
    tier3_participation,pay_frequency,effective_from,reason,evidence_reference
  ) values(
    p_tenant,p_employee,p_employment_relationship,p_tax_treatment,p_pension_status,
    p_tier3_participation,p_pay_frequency,p_effective_from,p_reason,p_evidence_reference
  ) returning id into v_id;

  update unimis.hrc_payroll_profiles
  set tier3_participation_mode=p_tier3_participation
  where tenant_id=p_tenant and employee_id=p_employee;

  return v_id;
end $$;

grant execute on function unimis.payroll_set_worker_classification(
  uuid,uuid,text,text,text,text,text,date,text,text
) to authenticated;




-- Refresh Supabase/PostgREST schema cache after this stage.
NOTIFY pgrst, 'reload schema';
