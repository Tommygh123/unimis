-- CONTINUATION: UniMIS Build 172 HR/Payroll repair
set search_path=unimis,public;

-- SOURCE 202610180001_integrated_payroll_engine_review.sql
-- HRPayrollCore 009d - integrated payroll engine + review breakdown
-- Uses effective worker classification and Tier 3 organization setup during calculation.
-- Adds review snapshot columns; historical posted runs are not recalculated.

alter table unimis.hrc_payroll_run_employees
 add column if not exists allowances_total numeric(14,2) not null default 0,
 add column if not exists overtime_total numeric(14,2) not null default 0,
 add column if not exists bonus_total numeric(14,2) not null default 0,
 add column if not exists arrears_other_earnings numeric(14,2) not null default 0,
 add column if not exists loan_deductions numeric(14,2) not null default 0,
 add column if not exists other_nonloan_deductions numeric(14,2) not null default 0;

create or replace function unimis.payroll_calculate_run(p_tenant uuid,p_period uuid)
returns uuid language plpgsql security definer set search_path=unimis as $$
declare r uuid; rn text; rec record; re uuid; pend date; country text; pr unimis.hrc_payroll_pension_rules%rowtype;
 basic numeric; earn numeric; ded numeric; taxable_extra numeric; pretax numeric; gross numeric; taxable numeric; insurable numeric; emp_pen numeric; er_pen numeric; tier1 numeric; tier2 numeric;
 pf_emp numeric; pf_er numeric; relief numeric; cfg jsonb; cls record; org_pf_emp numeric; org_pf_er numeric; pf_emp_rate numeric; pf_er_rate numeric; tier3_ok boolean; rel text; pension_mode text; tax_mode text; allowances numeric; loans numeric; chargeable numeric; tx numeric; net numeric; adjearn numeric; adjded numeric; adjpretax numeric; bonus_amt numeric; overtime_amt numeric; normal_adj_earn numeric; ot_tax numeric; bonus_tax numeric; bonus_concession numeric;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','payroll_manager','payroll_officer']) then raise exception 'Payroll access denied'; end if;
 select end_date into pend from unimis.hrc_payroll_periods where id=p_period and tenant_id=p_tenant; if pend is null then raise exception 'Invalid payroll period'; end if;
 select coalesce(country_code,'GH') into country from unimis.hrc_payroll_settings where tenant_id=p_tenant; country:=coalesce(country,'GH');
 select * into pr from unimis.hrc_payroll_pension_rules x where x.country_code=country and x.active and x.effective_from<=pend and (x.effective_to is null or x.effective_to>=pend) and (x.tenant_id=p_tenant or x.tenant_id is null) order by (x.tenant_id is not null) desc,x.effective_from desc limit 1;
 select coalesce(config,'{}'::jsonb) into cfg from unimis.hrc_payroll_setup_configs where tenant_id=p_tenant and lower(section)='tier3' limit 1; cfg:=coalesce(cfg,'{}'::jsonb);
 if country='GH' and not exists(select 1 from unimis.hrc_payroll_tax_bands b where b.country_code='GH' and b.active and b.effective_from<=pend and (b.effective_to is null or b.effective_to>=pend) and (b.tenant_id=p_tenant or b.tenant_id is null)) then raise exception 'No effective PAYE bands configured for payroll period end %',pend; end if;
 select id into r from unimis.hrc_payroll_runs where tenant_id=p_tenant and period_id=p_period;
 if r is null then rn:='RUN-'||to_char(pend,'YYYYMM')||'-'||lpad((1+(select count(*) from unimis.hrc_payroll_runs where tenant_id=p_tenant))::text,3,'0'); insert into unimis.hrc_payroll_runs(tenant_id,period_id,run_no,status,created_by) values(p_tenant,p_period,rn,'draft',auth.uid()) returning id into r;
 else if exists(select 1 from unimis.hrc_payroll_runs where id=r and status in ('approved','posted')) then raise exception 'Approved/posted payroll cannot be recalculated'; end if; delete from unimis.hrc_payroll_run_employees where run_id=r; end if;
 for rec in select e.*,pp.tax_residency,pp.worker_tax_category,pp.staff_category,pp.pension_tier1_enabled,pp.pension_tier2_enabled,pp.provident_fund_enabled,pp.provident_employee_rate,pp.provident_employer_rate,pp.tier3_participation_mode,pp.provident_effective_from,pp.provident_effective_to from unimis.hrc_hr_employees e join unimis.hrc_payroll_profiles pp on pp.employee_id=e.id and pp.active where e.tenant_id=p_tenant and e.employment_status='active' loop
  select c.* into cls from unimis.hrc_payroll_worker_classifications c where c.tenant_id=p_tenant and c.employee_id=rec.id and c.effective_from<=pend and (c.effective_to is null or c.effective_to>=pend) order by c.effective_from desc limit 1;
  rel:=coalesce(cls.employment_relationship,case when lower(coalesce(rec.employment_type,'regular'))='permanent' then 'regular' else lower(coalesce(rec.employment_type,'regular')) end);
  tax_mode:=coalesce(cls.tax_treatment,case when tax_mode='non_resident' then 'non_resident' when rec.worker_tax_category='casual' then 'casual_worker' when rec.worker_tax_category='temporary' then 'temporary_worker' else 'standard_paye' end);
  pension_mode:=coalesce(cls.pension_status,'active_contributor');
  if pension_mode='pending_review' then raise exception 'Payroll blocked: % (%) pension status is Pending Review',concat_ws(' ',rec.first_name,rec.last_name),rec.employee_no; end if;
  select coalesce((select sh.new_salary from unimis.hrc_hr_salary_history sh where sh.employee_id=rec.id and sh.effective_from<=pend order by sh.effective_from desc,sh.created_at desc limit 1),(select c.basic_salary from unimis.hrc_hr_employment_contracts c where c.employee_id=rec.id and c.status='active' order by c.start_date desc limit 1),0) into basic;
  select coalesce(sum(case when pc.component_type='earning' then pec.amount else 0 end),0),coalesce(sum(case when pc.component_type='deduction' then pec.amount else 0 end),0),coalesce(sum(case when pc.component_type='earning' and pc.taxable then pec.amount else 0 end),0),coalesce(sum(case when pc.component_type='deduction' and pc.pre_tax then pec.amount else 0 end),0) into earn,ded,taxable_extra,pretax from unimis.hrc_payroll_employee_components pec join unimis.hrc_payroll_components pc on pc.id=pec.component_id where pec.employee_id=rec.id and pec.tenant_id=p_tenant and pec.effective_from<=pend and (pec.effective_to is null or pec.effective_to>=pend) and pc.code<>'BASIC';
  select coalesce(sum(case when adjustment_type in ('earning','arrears') then amount else 0 end),0),coalesce(sum(case when adjustment_type in ('deduction','loan','unpaid_absence') then amount else 0 end),0),coalesce(sum(case when adjustment_type='pre_tax_deduction' then amount else 0 end),0),coalesce(sum(case when adjustment_type='bonus' then amount else 0 end),0),coalesce(sum(case when adjustment_type='overtime' then amount else 0 end),0) into normal_adj_earn,adjded,adjpretax,bonus_amt,overtime_amt from unimis.hrc_payroll_adjustments where tenant_id=p_tenant and employee_id=rec.id and period_id=p_period and status='approved';
  allowances:=earn; adjearn:=normal_adj_earn+bonus_amt+overtime_amt; gross:=basic+earn+adjearn; taxable:=basic+taxable_extra+normal_adj_earn;
  insurable:=least(greatest(basic,coalesce(pr.minimum_insurable,0)),coalesce(pr.maximum_insurable,basic)); emp_pen:=case when pension_mode in ('active_contributor','legacy_special') and rec.pension_tier1_enabled then round(insurable*coalesce(pr.employee_rate,0)/100,2) else 0 end; er_pen:=case when pension_mode in ('active_contributor','legacy_special') and rec.pension_tier1_enabled then round(insurable*coalesce(pr.employer_rate,0)/100,2) else 0 end; tier1:=case when pension_mode in ('active_contributor','legacy_special') and rec.pension_tier1_enabled then round(insurable*coalesce(pr.tier1_total_rate,0)/100,2) else 0 end; tier2:=case when pension_mode in ('active_contributor','legacy_special') and rec.pension_tier2_enabled then round(insurable*coalesce(pr.tier2_total_rate,0)/100,2) else 0 end;
  org_pf_emp:=coalesce(nullif(cfg->>'employee_default_rate','')::numeric,0); org_pf_er:=coalesce(nullif(cfg->>'employer_default_rate','')::numeric,0);
  pf_emp_rate:=case when coalesce((cfg->>'employee_rate_variable')::boolean,false) and coalesce(rec.provident_employee_rate,0)>0 and rec.provident_employee_rate<>org_pf_emp then rec.provident_employee_rate else org_pf_emp end;
  pf_er_rate:=case when coalesce((cfg->>'employer_rate_variable')::boolean,false) and coalesce(rec.provident_employer_rate,0)>0 and rec.provident_employer_rate<>org_pf_er then rec.provident_employer_rate else org_pf_er end;
  tier3_ok:=coalesce((cfg->>'enabled')::boolean,false) and coalesce(cls.tier3_participation,rec.tier3_participation_mode,'not_participating')='participating' and
    case when pension_mode='pensioner_retiree' then coalesce((cfg->>'eligible_pensioner')::boolean,false) when rel='regular' then coalesce((cfg->>'eligible_regular')::boolean,true) when rel='fixed_term' then coalesce((cfg->>'eligible_fixed_term')::boolean,true) when rel='part_time' then coalesce((cfg->>'eligible_part_time')::boolean,true) when rel='temporary' then coalesce((cfg->>'eligible_temporary')::boolean,false) when rel='casual' then coalesce((cfg->>'eligible_casual')::boolean,false) when rel='intern' then coalesce((cfg->>'eligible_intern')::boolean,false) when rel='national_service' then coalesce((cfg->>'eligible_national_service')::boolean,false) when rel='locum' then coalesce((cfg->>'eligible_locum')::boolean,false) when rel='consultant' then coalesce((cfg->>'eligible_consultant')::boolean,false) else false end
    and (rec.provident_effective_from is null or rec.provident_effective_from<=pend) and (rec.provident_effective_to is null or rec.provident_effective_to>=pend);
  pf_emp:=case when tier3_ok then round(basic*pf_emp_rate/100,2) else 0 end; pf_er:=case when tier3_ok then round(basic*pf_er_rate/100,2) else 0 end;
  select coalesce(sum(case when rt.calculation_type='percent_income' then taxable*coalesce(rt.percent_rate,0)/100 else coalesce(er.approved_annual_amount,case when rt.calculation_type='per_unit_annual' then rt.annual_amount*least(er.units,coalesce(rt.max_units,er.units)) else rt.annual_amount end,0) end)/12,0) into relief from unimis.hrc_payroll_employee_reliefs er join unimis.hrc_payroll_relief_types rt on rt.id=er.relief_type_id where er.tenant_id=p_tenant and er.employee_id=rec.id and er.approved and er.relief_status='active' and er.tax_year=extract(year from pend)::int and er.effective_from<=pend and (er.effective_to is null or er.effective_to>=pend);
  chargeable:=greatest(taxable-emp_pen-least(pf_emp+pf_er,basic*coalesce(pr.provident_tax_relief_cap_rate,0)/100)-pretax-adjpretax-relief,0);
  if tax_mode='exempt' then tx:=0; ot_tax:=0; bonus_tax:=0;
  elsif tax_mode='casual_worker' then tx:=round(gross*0.05,2); ot_tax:=0; bonus_tax:=0;
  else
   tx:=case when tax_mode='non_resident' then round(chargeable*0.25,2) else unimis.payroll_progressive_tax(p_tenant,country,pend,chargeable) end;
   if tax_mode='non_resident' then ot_tax:=round(overtime_amt*0.20,2); bonus_tax:=round(bonus_amt*0.20,2);
   else
    if rec.staff_category='junior' and basic*12<=18000 then ot_tax:=round(least(overtime_amt,basic*0.5)*0.05+greatest(overtime_amt-basic*0.5,0)*0.10,2); else taxable:=taxable+overtime_amt; tx:=unimis.payroll_progressive_tax(p_tenant,country,pend,greatest(chargeable+overtime_amt,0)); ot_tax:=0; end if;
    bonus_concession:=least(bonus_amt,basic*12*0.15); bonus_tax:=round(bonus_concession*0.05,2); if bonus_amt>bonus_concession then tx:=tx+(unimis.payroll_progressive_tax(p_tenant,country,pend,chargeable+(bonus_amt-bonus_concession))-unimis.payroll_progressive_tax(p_tenant,country,pend,chargeable)); end if;
   end if; tx:=round(tx+ot_tax+bonus_tax,2);
  end if;
  select coalesce(sum(amount),0) into loans from unimis.hrc_payroll_adjustments where tenant_id=p_tenant and employee_id=rec.id and period_id=p_period and status='approved' and adjustment_type='loan';
  net:=gross-emp_pen-pf_emp-tx-ded-adjded-pretax-adjpretax;
  insert into unimis.hrc_payroll_run_employees(tenant_id,run_id,employee_id,employee_no,employee_name,basic_salary,other_earnings,gross_pay,employee_pension,employer_pension,tax,other_deductions,net_pay,taxable_income,chargeable_income,tier1_total,tier2_total,provident_employee,provident_employer,tax_relief,employer_cost,allowances_total,overtime_total,bonus_total,arrears_other_earnings,loan_deductions,other_nonloan_deductions) values(p_tenant,r,rec.id,rec.employee_no,concat_ws(' ',rec.first_name,rec.other_names,rec.last_name),basic,earn+adjearn,gross,emp_pen,er_pen,tx,ded+adjded+pretax+adjpretax,net,taxable,chargeable,tier1,tier2,pf_emp,pf_er,relief,gross+er_pen+pf_er,allowances,overtime_amt,bonus_amt,normal_adj_earn,loans,greatest(ded+adjded+pretax+adjpretax-loans,0)) returning id into re;
  insert into unimis.hrc_payroll_run_items(tenant_id,run_employee_id,component_code,component_name,component_type,amount,taxable,pensionable) values(p_tenant,re,'BASIC','Basic Salary','earning',basic,true,true),(p_tenant,re,'SSNIT-EE','Employee SSNIT','deduction',emp_pen,false,false),(p_tenant,re,'PAYE','PAYE / employment tax','deduction',tx,false,false);
  if pf_emp>0 then insert into unimis.hrc_payroll_run_items(tenant_id,run_employee_id,component_code,component_name,component_type,amount,taxable,pensionable) values(p_tenant,re,'TIER3-EE','Tier 3 / PF Employee','deduction',pf_emp,false,false); end if;
  if relief>0 then insert into unimis.hrc_payroll_run_items(tenant_id,run_employee_id,component_code,component_name,component_type,amount,taxable,pensionable) values(p_tenant,re,'RELIEF','Approved Tax Relief','relief',relief,false,false); end if;
 end loop;
 update unimis.hrc_payroll_runs prun set status='calculated',employee_count=x.cnt,gross_total=x.gross,deduction_total=x.ded,employee_pension_total=x.ep,employer_pension_total=x.erp,tax_total=x.tax,net_total=x.net from (select count(*) cnt,coalesce(sum(gross_pay),0) gross,coalesce(sum(other_deductions),0) ded,coalesce(sum(employee_pension),0) ep,coalesce(sum(employer_pension),0) erp,coalesce(sum(tax),0) tax,coalesce(sum(net_pay),0) net from unimis.hrc_payroll_run_employees where run_id=r)x where prun.id=r;
 update unimis.hrc_payroll_periods set status='review' where id=p_period; return r;
end $$;
grant execute on function unimis.payroll_calculate_run(uuid,uuid) to authenticated;


-- SOURCE 202610180002_staff_payroll_statements.sql
create table if not exists unimis.hrc_payroll_staff_statements(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 payroll_run_id uuid not null references unimis.hrc_payroll_runs(id) on delete cascade,
 run_employee_id uuid not null references unimis.hrc_payroll_run_employees(id) on delete cascade,
 employee_id uuid not null references unimis.hrc_hr_employees(id), amount_due numeric(14,2) not null default 0,
 amount_paid numeric(14,2) not null default 0,balance numeric(14,2) not null default 0,
 status text not null default 'unpaid' check(status in('unpaid','part_paid','paid')),
 last_payment_date date,last_payment_reference text,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(run_employee_id));
create table if not exists unimis.hrc_payroll_staff_payment_transactions(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 statement_id uuid not null references unimis.hrc_payroll_staff_statements(id) on delete cascade,
 amount numeric(14,2) not null check(amount>0),payment_date date not null default current_date,reference text not null,
 recorded_by uuid default auth.uid(),created_at timestamptz not null default now());
alter table unimis.hrc_payroll_staff_statements enable row level security;alter table unimis.hrc_payroll_staff_payment_transactions enable row level security;
drop policy if exists staff_statements_tenant on unimis.hrc_payroll_staff_statements;create policy staff_statements_tenant on unimis.hrc_payroll_staff_statements for all to authenticated using(unimis.is_tenant_member(tenant_id)) with check(unimis.is_tenant_member(tenant_id));
drop policy if exists staff_payment_tx_tenant on unimis.hrc_payroll_staff_payment_transactions;create policy staff_payment_tx_tenant on unimis.hrc_payroll_staff_payment_transactions for all to authenticated using(unimis.is_tenant_member(tenant_id)) with check(unimis.is_tenant_member(tenant_id));
create or replace function unimis.payroll_generate_staff_statements(p_tenant uuid,p_run uuid) returns integer language plpgsql security definer set search_path=unimis as $$declare n integer;begin if not unimis.has_tenant_role(p_tenant,array['owner','administrator','accountant','finance_manager','payroll_manager','payroll_officer']) then raise exception 'Payroll access denied';end if;if not exists(select 1 from hrc_payroll_runs where id=p_run and tenant_id=p_tenant and status='posted') then raise exception 'Payroll must be posted before staff statements are generated';end if;insert into hrc_payroll_staff_statements(tenant_id,payroll_run_id,run_employee_id,employee_id,amount_due,amount_paid,balance,status) select p_tenant,p_run,r.id,r.employee_id,r.net_pay,0,r.net_pay,'unpaid' from hrc_payroll_run_employees r where r.run_id=p_run on conflict(run_employee_id) do update set amount_due=excluded.amount_due,balance=greatest(excluded.amount_due-hrc_payroll_staff_statements.amount_paid,0),status=case when hrc_payroll_staff_statements.amount_paid>=excluded.amount_due then 'paid' when hrc_payroll_staff_statements.amount_paid>0 then 'part_paid' else 'unpaid' end,updated_at=now();get diagnostics n=row_count;return n;end$$;
create or replace function unimis.payroll_record_staff_payment(p_tenant uuid,p_statement uuid,p_amount numeric,p_reference text) returns jsonb language plpgsql security definer set search_path=unimis as $$declare s hrc_payroll_staff_statements%rowtype;np numeric;nb numeric;begin if not unimis.has_tenant_role(p_tenant,array['owner','administrator','accountant','finance_manager','payroll_manager','payroll_officer']) then raise exception 'Payroll access denied';end if;select * into s from hrc_payroll_staff_statements where id=p_statement and tenant_id=p_tenant for update;if s.id is null then raise exception 'Staff payroll statement not found';end if;if p_amount<=0 or p_amount>s.balance then raise exception 'Payment must be greater than zero and not exceed outstanding balance';end if;insert into hrc_payroll_staff_payment_transactions(tenant_id,statement_id,amount,reference) values(p_tenant,p_statement,p_amount,p_reference);np:=s.amount_paid+p_amount;nb:=greatest(s.amount_due-np,0);update hrc_payroll_staff_statements set amount_paid=np,balance=nb,status=case when nb=0 then 'paid' else 'part_paid' end,last_payment_date=current_date,last_payment_reference=p_reference,updated_at=now() where id=s.id;return jsonb_build_object('ok',true,'paid',np,'balance',nb);end$$;
grant execute on function unimis.payroll_generate_staff_statements(uuid,uuid) to authenticated;grant execute on function unimis.payroll_record_staff_payment(uuid,uuid,numeric,text) to authenticated;


-- SOURCE 202610220001_009f_complete_demo_seed.sql
-- HRPayrollCore 009f: repeatable complete demo seed for fresh local installations.
-- Runs only when an Owner/Administrator clicks Load complete demo data.
create or replace function unimis.seed_hrpayroll_demo(p_tenant uuid)
returns void language plpgsql security definer set search_path=unimis as $$
declare
 b uuid; le uuid; d1 uuid; d2 uuid; d3 uuid; g1 uuid; g2 uuid; p1 uuid; p2 uuid; p3 uuid; pg uuid;
 e1 uuid; e2 uuid; e3 uuid; e4 uuid; c uuid; rt uuid; per uuid; cyc uuid;
 mstart date:=date_trunc('month',current_date)::date; mend date:=(date_trunc('month',current_date)+interval '1 month - 1 day')::date;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator']) then raise exception 'Owner/admin required'; end if;
 select id into b from unimis.hrc_branches where tenant_id=p_tenant order by created_at limit 1;
 if b is null then
   select id into le from unimis.hrc_legal_entities where tenant_id=p_tenant order by created_at limit 1;
   if le is null then insert into unimis.hrc_legal_entities(tenant_id,name) select p_tenant,name from unimis.hrc_tenants where id=p_tenant returning id into le; end if;
   insert into unimis.hrc_branches(tenant_id,legal_entity_id,code,name,city) values(p_tenant,le,'HQ','Head Office','Kumasi') returning id into b;
 end if;
 select id into pg from unimis.hrc_payroll_pay_groups where tenant_id=p_tenant and active order by created_at limit 1;
 if pg is null then insert into unimis.hrc_payroll_pay_groups(tenant_id,code,name,frequency) values(p_tenant,'MONTHLY','Monthly Payroll','monthly') returning id into pg; end if;

 insert into unimis.hrc_departments(tenant_id,branch_id,code,name) values
 (p_tenant,b,'ADM','Administration'),(p_tenant,b,'FIN','Finance'),(p_tenant,b,'OPS','Operations')
 on conflict(tenant_id,code) do update set name=excluded.name,branch_id=coalesce(unimis.hrc_departments.branch_id,excluded.branch_id);
 select id into d1 from unimis.hrc_departments where tenant_id=p_tenant and code='ADM'; select id into d2 from unimis.hrc_departments where tenant_id=p_tenant and code='FIN'; select id into d3 from unimis.hrc_departments where tenant_id=p_tenant and code='OPS';
 insert into unimis.hrc_hr_job_grades(tenant_id,code,name,min_salary,max_salary) values
 (p_tenant,'G1','Officer',2500,6000),(p_tenant,'G2','Senior Officer',4500,9000)
 on conflict(tenant_id,code) do update set name=excluded.name,min_salary=excluded.min_salary,max_salary=excluded.max_salary;
 select id into g1 from unimis.hrc_hr_job_grades where tenant_id=p_tenant and code='G1'; select id into g2 from unimis.hrc_hr_job_grades where tenant_id=p_tenant and code='G2';
 insert into unimis.hrc_hr_positions(tenant_id,department_id,grade_id,code,title) values
 (p_tenant,d1,g1,'ADMIN-OFF','Administrative Officer'),(p_tenant,d2,g2,'ACCT-OFF','Accounts Officer'),(p_tenant,d3,g1,'OPS-OFF','Operations Officer')
 on conflict(tenant_id,code) do update set title=excluded.title,department_id=excluded.department_id,grade_id=excluded.grade_id;
 select id into p1 from unimis.hrc_hr_positions where tenant_id=p_tenant and code='ADMIN-OFF'; select id into p2 from unimis.hrc_hr_positions where tenant_id=p_tenant and code='ACCT-OFF'; select id into p3 from unimis.hrc_hr_positions where tenant_id=p_tenant and code='OPS-OFF';

 insert into unimis.hrc_hr_employees(tenant_id,employee_no,first_name,last_name,email,branch_id,department_id,position_id,hire_date,employment_type,work_schedule,pension_status)
 values(p_tenant,'EMP001','Ama','Mensah','ama.mensah@example.test',b,d1,p1,current_date-500,'regular','full_time','active_contributor')
 on conflict(tenant_id,employee_no) do update set first_name='Ama',last_name='Mensah',department_id=d1,position_id=p1,employment_type='regular',employment_status='active' returning id into e1;
 if e1 is null then select id into e1 from unimis.hrc_hr_employees where tenant_id=p_tenant and employee_no='EMP001'; end if;
 insert into unimis.hrc_hr_employees(tenant_id,employee_no,first_name,last_name,email,branch_id,department_id,position_id,hire_date,employment_type,work_schedule,pension_status)
 values(p_tenant,'EMP002','Kwame','Asare','kwame.asare@example.test',b,d2,p2,current_date-420,'regular','full_time','active_contributor')
 on conflict(tenant_id,employee_no) do update set first_name='Kwame',last_name='Asare',department_id=d2,position_id=p2,employment_type='regular',employment_status='active' returning id into e2;
 if e2 is null then select id into e2 from unimis.hrc_hr_employees where tenant_id=p_tenant and employee_no='EMP002'; end if;
 insert into unimis.hrc_hr_employees(tenant_id,employee_no,first_name,last_name,email,branch_id,department_id,position_id,hire_date,employment_type,work_schedule,pension_status)
 values(p_tenant,'EMP003','Esi','Agyeman','esi.agyeman@example.test',b,d3,p3,current_date-180,'fixed_term','full_time','active_contributor')
 on conflict(tenant_id,employee_no) do update set first_name='Esi',last_name='Agyeman',department_id=d3,position_id=p3,employment_type='fixed_term',employment_status='active' returning id into e3;
 if e3 is null then select id into e3 from unimis.hrc_hr_employees where tenant_id=p_tenant and employee_no='EMP003'; end if;
 insert into unimis.hrc_hr_employees(tenant_id,employee_no,first_name,last_name,email,branch_id,department_id,position_id,hire_date,employment_type,work_schedule,pension_status)
 values(p_tenant,'EMP004','Kojo','Owusu','kojo.owusu@example.test',b,d3,p3,current_date-90,'casual','part_time','not_applicable')
 on conflict(tenant_id,employee_no) do update set first_name='Kojo',last_name='Owusu',department_id=d3,position_id=p3,employment_type='casual',employment_status='active' returning id into e4;
 if e4 is null then select id into e4 from unimis.hrc_hr_employees where tenant_id=p_tenant and employee_no='EMP004'; end if;

 -- Current contracts: do not duplicate on repeat runs.
 if not exists(select 1 from unimis.hrc_hr_employment_contracts where tenant_id=p_tenant and employee_id=e1 and status='active') then insert into unimis.hrc_hr_employment_contracts(tenant_id,employee_id,contract_type,start_date,basic_salary,pay_frequency,status) values(p_tenant,e1,'regular',current_date-500,4200,'monthly','active'); end if;
 if not exists(select 1 from unimis.hrc_hr_employment_contracts where tenant_id=p_tenant and employee_id=e2 and status='active') then insert into unimis.hrc_hr_employment_contracts(tenant_id,employee_id,contract_type,start_date,basic_salary,pay_frequency,status) values(p_tenant,e2,'regular',current_date-420,5000,'monthly','active'); end if;
 if not exists(select 1 from unimis.hrc_hr_employment_contracts where tenant_id=p_tenant and employee_id=e3 and status='active') then insert into unimis.hrc_hr_employment_contracts(tenant_id,employee_id,contract_type,start_date,end_date,basic_salary,pay_frequency,status) values(p_tenant,e3,'fixed_term',current_date-180,current_date+185,3200,'monthly','active'); end if;
 if not exists(select 1 from unimis.hrc_hr_employment_contracts where tenant_id=p_tenant and employee_id=e4 and status='active') then insert into unimis.hrc_hr_employment_contracts(tenant_id,employee_id,contract_type,start_date,basic_salary,pay_frequency,status) values(p_tenant,e4,'casual',current_date-90,1800,'monthly','active'); end if;

 insert into unimis.hrc_payroll_profiles(tenant_id,employee_id,pay_group_id,bank_name,bank_account_name,bank_account_number,payment_method,tier3_participation_mode,provident_fund_enabled,provident_employee_rate,provident_employer_rate,active) values
 (p_tenant,e1,pg,'Demo Bank','Ama Mensah','001000001','bank','participating',true,1,5,true),
 (p_tenant,e2,pg,'Demo Bank','Kwame Asare','001000002','bank','not_participating',false,0,0,true),
 (p_tenant,e3,pg,'Demo Bank','Esi Agyeman','001000003','bank','not_participating',false,0,0,true),
 (p_tenant,e4,pg,'Mobile Money','Kojo Owusu','0240000000','momo','not_participating',false,0,0,true)
 on conflict(tenant_id,employee_id) do update set pay_group_id=excluded.pay_group_id,bank_name=excluded.bank_name,bank_account_name=excluded.bank_account_name,bank_account_number=excluded.bank_account_number,payment_method=excluded.payment_method,active=true;

 insert into unimis.hrc_payroll_worker_classifications(tenant_id,employee_id,employment_relationship,tax_treatment,pension_status,tier3_participation,pay_frequency,effective_from,approved,approved_by,approved_at,reason)
 values
 (p_tenant,e1,'regular','standard_paye','active_contributor','participating','monthly',mstart,true,auth.uid(),now(),'009f demo'),
 (p_tenant,e2,'regular','standard_paye','active_contributor','not_participating','monthly',mstart,true,auth.uid(),now(),'009f demo'),
 (p_tenant,e3,'fixed_term','standard_paye','active_contributor','not_participating','monthly',mstart,true,auth.uid(),now(),'009f demo'),
 (p_tenant,e4,'casual','casual_worker','not_applicable','not_participating','monthly',mstart,true,auth.uid(),now(),'009f demo')
 on conflict(tenant_id,employee_id) where effective_to is null do update set employment_relationship=excluded.employment_relationship,tax_treatment=excluded.tax_treatment,pension_status=excluded.pension_status,tier3_participation=excluded.tier3_participation,pay_frequency=excluded.pay_frequency,approved=true,approved_by=auth.uid(),approved_at=now();

 -- Demo payroll catalogue and Ama's known recurring inputs.
 insert into unimis.hrc_payroll_components(tenant_id,code,name,component_type,taxable,pensionable,calculation_type,default_amount,tax_treatment,pre_tax,recurring,active,employee_or_employer,requires_consent,requires_approval,effective_from,description) values
 (p_tenant,'TRANSPORT','Transport Allowance','earning',true,false,'fixed',100,'graduated',false,true,true,'employee',false,true,mstart,'009f demo allowance'),
 (p_tenant,'CHILD_EDU_ALLOW','Child Education Allowance','earning',true,false,'fixed',10,'graduated',false,true,true,'employee',false,true,mstart,'009f demo allowance'),
 (p_tenant,'GARDEN_BOY','Garden Boy Allowance','earning',true,false,'fixed',10,'graduated',false,true,true,'employee',false,true,mstart,'009f demo allowance'),
 (p_tenant,'HOUSE_HELP','House Help Allowance','earning',true,false,'fixed',10,'graduated',false,true,true,'employee',false,true,mstart,'009f demo allowance'),
 (p_tenant,'STAFF_INS','Staff Insurance','deduction',false,false,'fixed',100,'post_tax',false,true,true,'employee',true,true,mstart,'009f demo deduction'),
 (p_tenant,'STAFF_TRANSPORT','Staff Transport','deduction',false,false,'fixed',20,'post_tax',false,true,true,'employee',true,true,mstart,'009f demo deduction')
 on conflict(tenant_id,code) do update set name=excluded.name,component_type=excluded.component_type,active=true;
 for c in select id from unimis.hrc_payroll_components where tenant_id=p_tenant and code in ('TRANSPORT','CHILD_EDU_ALLOW','GARDEN_BOY','HOUSE_HELP','STAFF_INS','STAFF_TRANSPORT') loop
   insert into unimis.hrc_payroll_employee_components(tenant_id,employee_id,component_id,amount,effective_from)
   select p_tenant,e1,c.id,case (select code from unimis.hrc_payroll_components where id=c.id) when 'TRANSPORT' then 100 when 'STAFF_INS' then 100 when 'STAFF_TRANSPORT' then 20 else 10 end,mstart
   on conflict(employee_id,component_id,effective_from) do update set amount=excluded.amount;
 end loop;

 insert into unimis.hrc_payroll_setup_configs(tenant_id,section,config) values(p_tenant,'tier3',jsonb_build_object('enabled',true,'participationMode','employee_opt_in','employeeRate',1,'employerRate',5,'basis','basic_salary','employeeRateMayVary',true,'employerRateMayVary',false))
 on conflict(tenant_id,section) do update set config=excluded.config,updated_at=now();

 select id into per from unimis.hrc_payroll_periods where tenant_id=p_tenant and start_date=mstart and end_date=mend order by created_at limit 1;
 if per is null then insert into unimis.hrc_payroll_periods(tenant_id,pay_group_id,name,start_date,end_date,pay_date,status) values(p_tenant,pg,to_char(mstart,'FMMonth YYYY'),mstart,mend,mend,'open') returning id into per; end if;
 -- Bonus 22 reproduces the known Ama test gross of 4,352 only if all four allowances are active; kept as a visible period input.
 if not exists(select 1 from unimis.hrc_payroll_adjustments where tenant_id=p_tenant and employee_id=e1 and period_id=per and source_reference='009F-BONUS-AMA') then
   insert into unimis.hrc_payroll_adjustments(tenant_id,employee_id,period_id,adjustment_type,code,description,amount,taxable,pensionable,status,source_module,source_reference,created_by) values(p_tenant,e1,per,'bonus','BONUS','Demo period bonus',22,true,false,'approved','demo','009F-BONUS-AMA',auth.uid());
 end if;

 select id into rt from unimis.hrc_payroll_relief_types where country_code='GH' and code='CHILD_EDU' and (tenant_id=p_tenant or tenant_id is null) order by (tenant_id is not null) desc limit 1;
 if rt is not null then
  insert into unimis.hrc_payroll_employee_reliefs(tenant_id,employee_id,relief_type_id,tax_year,units,approved_annual_amount,approved,effective_from,reference,relief_status,approval_date)
  values(p_tenant,e1,rt,extract(year from current_date)::int,1,50,true,date_trunc('year',current_date)::date,'009F-DEMO-RELIEF','active',current_date)
  on conflict(employee_id,relief_type_id,tax_year) do update set approved=true,approved_annual_amount=50,relief_status='active',approval_date=current_date;
 end if;

 -- Performance demo now seeds after employees exist (important on a fresh PC).
 if to_regclass('unimis.hrc_hr_performance_cycles') is not null then
   insert into unimis.hrc_hr_performance_cycles(tenant_id,name,cycle_type,start_date,end_date,status) values(p_tenant,extract(year from current_date)::text||' Annual Performance Review','annual',date_trunc('year',current_date)::date,(date_trunc('year',current_date)+interval '1 year - 1 day')::date,'open') on conflict do nothing;
 end if;
 insert into unimis.hrc_payroll_settings(tenant_id) values(p_tenant) on conflict(tenant_id) do nothing;
 insert into unimis.hrc_audit_events(tenant_id,actor_id,module,action,record_type,record_id,details) values(p_tenant,auth.uid(),'core','demo.seeded','tenant',p_tenant,jsonb_build_object('package','009f','employees',4,'repeatable',true));
end $$;
grant execute on function unimis.seed_hrpayroll_demo(uuid) to authenticated;
notify pgrst, 'reload schema';


-- SOURCE 202610220002_009f1_seed_loop_fix.sql
-- HRPayrollCore 009f1: corrective replacement of demo seed function (fix component loop record).
-- Runs only when an Owner/Administrator clicks Load complete demo data.
create or replace function unimis.seed_hrpayroll_demo(p_tenant uuid)
returns void language plpgsql security definer set search_path=unimis as $$
declare
 b uuid; le uuid; d1 uuid; d2 uuid; d3 uuid; g1 uuid; g2 uuid; p1 uuid; p2 uuid; p3 uuid; pg uuid;
 e1 uuid; e2 uuid; e3 uuid; e4 uuid; rt uuid; per uuid; cyc uuid;
 c record;
 mstart date:=date_trunc('month',current_date)::date; mend date:=(date_trunc('month',current_date)+interval '1 month - 1 day')::date;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator']) then raise exception 'Owner/admin required'; end if;
 select id into b from unimis.hrc_branches where tenant_id=p_tenant order by created_at limit 1;
 if b is null then
   select id into le from unimis.hrc_legal_entities where tenant_id=p_tenant order by created_at limit 1;
   if le is null then insert into unimis.hrc_legal_entities(tenant_id,name) select p_tenant,name from unimis.hrc_tenants where id=p_tenant returning id into le; end if;
   insert into unimis.hrc_branches(tenant_id,legal_entity_id,code,name,city) values(p_tenant,le,'HQ','Head Office','Kumasi') returning id into b;
 end if;
 select id into pg from unimis.hrc_payroll_pay_groups where tenant_id=p_tenant and active order by created_at limit 1;
 if pg is null then insert into unimis.hrc_payroll_pay_groups(tenant_id,code,name,frequency) values(p_tenant,'MONTHLY','Monthly Payroll','monthly') returning id into pg; end if;

 insert into unimis.hrc_departments(tenant_id,branch_id,code,name) values
 (p_tenant,b,'ADM','Administration'),(p_tenant,b,'FIN','Finance'),(p_tenant,b,'OPS','Operations')
 on conflict(tenant_id,code) do update set name=excluded.name,branch_id=coalesce(unimis.hrc_departments.branch_id,excluded.branch_id);
 select id into d1 from unimis.hrc_departments where tenant_id=p_tenant and code='ADM'; select id into d2 from unimis.hrc_departments where tenant_id=p_tenant and code='FIN'; select id into d3 from unimis.hrc_departments where tenant_id=p_tenant and code='OPS';
 insert into unimis.hrc_hr_job_grades(tenant_id,code,name,min_salary,max_salary) values
 (p_tenant,'G1','Officer',2500,6000),(p_tenant,'G2','Senior Officer',4500,9000)
 on conflict(tenant_id,code) do update set name=excluded.name,min_salary=excluded.min_salary,max_salary=excluded.max_salary;
 select id into g1 from unimis.hrc_hr_job_grades where tenant_id=p_tenant and code='G1'; select id into g2 from unimis.hrc_hr_job_grades where tenant_id=p_tenant and code='G2';
 insert into unimis.hrc_hr_positions(tenant_id,department_id,grade_id,code,title) values
 (p_tenant,d1,g1,'ADMIN-OFF','Administrative Officer'),(p_tenant,d2,g2,'ACCT-OFF','Accounts Officer'),(p_tenant,d3,g1,'OPS-OFF','Operations Officer')
 on conflict(tenant_id,code) do update set title=excluded.title,department_id=excluded.department_id,grade_id=excluded.grade_id;
 select id into p1 from unimis.hrc_hr_positions where tenant_id=p_tenant and code='ADMIN-OFF'; select id into p2 from unimis.hrc_hr_positions where tenant_id=p_tenant and code='ACCT-OFF'; select id into p3 from unimis.hrc_hr_positions where tenant_id=p_tenant and code='OPS-OFF';

 insert into unimis.hrc_hr_employees(tenant_id,employee_no,first_name,last_name,email,branch_id,department_id,position_id,hire_date,employment_type,work_schedule,pension_status)
 values(p_tenant,'EMP001','Ama','Mensah','ama.mensah@example.test',b,d1,p1,current_date-500,'regular','full_time','active_contributor')
 on conflict(tenant_id,employee_no) do update set first_name='Ama',last_name='Mensah',department_id=d1,position_id=p1,employment_type='regular',employment_status='active' returning id into e1;
 if e1 is null then select id into e1 from unimis.hrc_hr_employees where tenant_id=p_tenant and employee_no='EMP001'; end if;
 insert into unimis.hrc_hr_employees(tenant_id,employee_no,first_name,last_name,email,branch_id,department_id,position_id,hire_date,employment_type,work_schedule,pension_status)
 values(p_tenant,'EMP002','Kwame','Asare','kwame.asare@example.test',b,d2,p2,current_date-420,'regular','full_time','active_contributor')
 on conflict(tenant_id,employee_no) do update set first_name='Kwame',last_name='Asare',department_id=d2,position_id=p2,employment_type='regular',employment_status='active' returning id into e2;
 if e2 is null then select id into e2 from unimis.hrc_hr_employees where tenant_id=p_tenant and employee_no='EMP002'; end if;
 insert into unimis.hrc_hr_employees(tenant_id,employee_no,first_name,last_name,email,branch_id,department_id,position_id,hire_date,employment_type,work_schedule,pension_status)
 values(p_tenant,'EMP003','Esi','Agyeman','esi.agyeman@example.test',b,d3,p3,current_date-180,'fixed_term','full_time','active_contributor')
 on conflict(tenant_id,employee_no) do update set first_name='Esi',last_name='Agyeman',department_id=d3,position_id=p3,employment_type='fixed_term',employment_status='active' returning id into e3;
 if e3 is null then select id into e3 from unimis.hrc_hr_employees where tenant_id=p_tenant and employee_no='EMP003'; end if;
 insert into unimis.hrc_hr_employees(tenant_id,employee_no,first_name,last_name,email,branch_id,department_id,position_id,hire_date,employment_type,work_schedule,pension_status)
 values(p_tenant,'EMP004','Kojo','Owusu','kojo.owusu@example.test',b,d3,p3,current_date-90,'casual','part_time','not_applicable')
 on conflict(tenant_id,employee_no) do update set first_name='Kojo',last_name='Owusu',department_id=d3,position_id=p3,employment_type='casual',employment_status='active' returning id into e4;
 if e4 is null then select id into e4 from unimis.hrc_hr_employees where tenant_id=p_tenant and employee_no='EMP004'; end if;

 -- Current contracts: do not duplicate on repeat runs.
 if not exists(select 1 from unimis.hrc_hr_employment_contracts where tenant_id=p_tenant and employee_id=e1 and status='active') then insert into unimis.hrc_hr_employment_contracts(tenant_id,employee_id,contract_type,start_date,basic_salary,pay_frequency,status) values(p_tenant,e1,'regular',current_date-500,4200,'monthly','active'); end if;
 if not exists(select 1 from unimis.hrc_hr_employment_contracts where tenant_id=p_tenant and employee_id=e2 and status='active') then insert into unimis.hrc_hr_employment_contracts(tenant_id,employee_id,contract_type,start_date,basic_salary,pay_frequency,status) values(p_tenant,e2,'regular',current_date-420,5000,'monthly','active'); end if;
 if not exists(select 1 from unimis.hrc_hr_employment_contracts where tenant_id=p_tenant and employee_id=e3 and status='active') then insert into unimis.hrc_hr_employment_contracts(tenant_id,employee_id,contract_type,start_date,end_date,basic_salary,pay_frequency,status) values(p_tenant,e3,'fixed_term',current_date-180,current_date+185,3200,'monthly','active'); end if;
 if not exists(select 1 from unimis.hrc_hr_employment_contracts where tenant_id=p_tenant and employee_id=e4 and status='active') then insert into unimis.hrc_hr_employment_contracts(tenant_id,employee_id,contract_type,start_date,basic_salary,pay_frequency,status) values(p_tenant,e4,'casual',current_date-90,1800,'monthly','active'); end if;

 insert into unimis.hrc_payroll_profiles(tenant_id,employee_id,pay_group_id,bank_name,bank_account_name,bank_account_number,payment_method,tier3_participation_mode,provident_fund_enabled,provident_employee_rate,provident_employer_rate,active) values
 (p_tenant,e1,pg,'Demo Bank','Ama Mensah','001000001','bank','participating',true,1,5,true),
 (p_tenant,e2,pg,'Demo Bank','Kwame Asare','001000002','bank','not_participating',false,0,0,true),
 (p_tenant,e3,pg,'Demo Bank','Esi Agyeman','001000003','bank','not_participating',false,0,0,true),
 (p_tenant,e4,pg,'Mobile Money','Kojo Owusu','0240000000','momo','not_participating',false,0,0,true)
 on conflict(tenant_id,employee_id) do update set pay_group_id=excluded.pay_group_id,bank_name=excluded.bank_name,bank_account_name=excluded.bank_account_name,bank_account_number=excluded.bank_account_number,payment_method=excluded.payment_method,active=true;

 insert into unimis.hrc_payroll_worker_classifications(tenant_id,employee_id,employment_relationship,tax_treatment,pension_status,tier3_participation,pay_frequency,effective_from,approved,approved_by,approved_at,reason)
 values
 (p_tenant,e1,'regular','standard_paye','active_contributor','participating','monthly',mstart,true,auth.uid(),now(),'009f demo'),
 (p_tenant,e2,'regular','standard_paye','active_contributor','not_participating','monthly',mstart,true,auth.uid(),now(),'009f demo'),
 (p_tenant,e3,'fixed_term','standard_paye','active_contributor','not_participating','monthly',mstart,true,auth.uid(),now(),'009f demo'),
 (p_tenant,e4,'casual','casual_worker','not_applicable','not_participating','monthly',mstart,true,auth.uid(),now(),'009f demo')
 on conflict(tenant_id,employee_id) where effective_to is null do update set employment_relationship=excluded.employment_relationship,tax_treatment=excluded.tax_treatment,pension_status=excluded.pension_status,tier3_participation=excluded.tier3_participation,pay_frequency=excluded.pay_frequency,approved=true,approved_by=auth.uid(),approved_at=now();

 -- Demo payroll catalogue and Ama's known recurring inputs.
 insert into unimis.hrc_payroll_components(tenant_id,code,name,component_type,taxable,pensionable,calculation_type,default_amount,tax_treatment,pre_tax,recurring,active,employee_or_employer,requires_consent,requires_approval,effective_from,description) values
 (p_tenant,'TRANSPORT','Transport Allowance','earning',true,false,'fixed',100,'graduated',false,true,true,'employee',false,true,mstart,'009f demo allowance'),
 (p_tenant,'CHILD_EDU_ALLOW','Child Education Allowance','earning',true,false,'fixed',10,'graduated',false,true,true,'employee',false,true,mstart,'009f demo allowance'),
 (p_tenant,'GARDEN_BOY','Garden Boy Allowance','earning',true,false,'fixed',10,'graduated',false,true,true,'employee',false,true,mstart,'009f demo allowance'),
 (p_tenant,'HOUSE_HELP','House Help Allowance','earning',true,false,'fixed',10,'graduated',false,true,true,'employee',false,true,mstart,'009f demo allowance'),
 (p_tenant,'STAFF_INS','Staff Insurance','deduction',false,false,'fixed',100,'post_tax',false,true,true,'employee',true,true,mstart,'009f demo deduction'),
 (p_tenant,'STAFF_TRANSPORT','Staff Transport','deduction',false,false,'fixed',20,'post_tax',false,true,true,'employee',true,true,mstart,'009f demo deduction')
 on conflict(tenant_id,code) do update set name=excluded.name,component_type=excluded.component_type,active=true;
 for c in select id from unimis.hrc_payroll_components where tenant_id=p_tenant and code in ('TRANSPORT','CHILD_EDU_ALLOW','GARDEN_BOY','HOUSE_HELP','STAFF_INS','STAFF_TRANSPORT') loop
   insert into unimis.hrc_payroll_employee_components(tenant_id,employee_id,component_id,amount,effective_from)
   select p_tenant,e1,c.id,case (select code from unimis.hrc_payroll_components where id=c.id) when 'TRANSPORT' then 100 when 'STAFF_INS' then 100 when 'STAFF_TRANSPORT' then 20 else 10 end,mstart
   on conflict(employee_id,component_id,effective_from) do update set amount=excluded.amount;
 end loop;

 insert into unimis.hrc_payroll_setup_configs(tenant_id,section,config) values(p_tenant,'tier3',jsonb_build_object('enabled',true,'participationMode','employee_opt_in','employeeRate',1,'employerRate',5,'basis','basic_salary','employeeRateMayVary',true,'employerRateMayVary',false))
 on conflict(tenant_id,section) do update set config=excluded.config,updated_at=now();

 select id into per from unimis.hrc_payroll_periods where tenant_id=p_tenant and start_date=mstart and end_date=mend order by created_at limit 1;
 if per is null then insert into unimis.hrc_payroll_periods(tenant_id,pay_group_id,name,start_date,end_date,pay_date,status) values(p_tenant,pg,to_char(mstart,'FMMonth YYYY'),mstart,mend,mend,'open') returning id into per; end if;
 -- Bonus 22 reproduces the known Ama test gross of 4,352 only if all four allowances are active; kept as a visible period input.
 if not exists(select 1 from unimis.hrc_payroll_adjustments where tenant_id=p_tenant and employee_id=e1 and period_id=per and source_reference='009F-BONUS-AMA') then
   insert into unimis.hrc_payroll_adjustments(tenant_id,employee_id,period_id,adjustment_type,code,description,amount,taxable,pensionable,status,source_module,source_reference,created_by) values(p_tenant,e1,per,'bonus','BONUS','Demo period bonus',22,true,false,'approved','demo','009F-BONUS-AMA',auth.uid());
 end if;

 select id into rt from unimis.hrc_payroll_relief_types where country_code='GH' and code='CHILD_EDU' and (tenant_id=p_tenant or tenant_id is null) order by (tenant_id is not null) desc limit 1;
 if rt is not null then
  insert into unimis.hrc_payroll_employee_reliefs(tenant_id,employee_id,relief_type_id,tax_year,units,approved_annual_amount,approved,effective_from,reference,relief_status,approval_date)
  values(p_tenant,e1,rt,extract(year from current_date)::int,1,50,true,date_trunc('year',current_date)::date,'009F-DEMO-RELIEF','active',current_date)
  on conflict(employee_id,relief_type_id,tax_year) do update set approved=true,approved_annual_amount=50,relief_status='active',approval_date=current_date;
 end if;

 -- Performance demo now seeds after employees exist (important on a fresh PC).
 if to_regclass('unimis.hrc_hr_performance_cycles') is not null then
   insert into unimis.hrc_hr_performance_cycles(tenant_id,name,cycle_type,start_date,end_date,status) values(p_tenant,extract(year from current_date)::text||' Annual Performance Review','annual',date_trunc('year',current_date)::date,(date_trunc('year',current_date)+interval '1 year - 1 day')::date,'open') on conflict do nothing;
 end if;
 insert into unimis.hrc_payroll_settings(tenant_id) values(p_tenant) on conflict(tenant_id) do nothing;
 insert into unimis.hrc_audit_events(tenant_id,actor_id,module,action,record_type,record_id,details) values(p_tenant,auth.uid(),'core','demo.seeded','tenant',p_tenant,jsonb_build_object('package','009f1','employees',4,'repeatable',true));
end $$;
grant execute on function unimis.seed_hrpayroll_demo(uuid) to authenticated;
notify pgrst, 'reload schema';


-- SOURCE 202610220003_009g_staff_salary_accounts.sql
-- 009g: richer staff salary payment transaction audit trail.
alter table unimis.hrc_payroll_staff_payment_transactions
  add column if not exists payment_method text,
  add column if not exists notes text,
  add column if not exists batch_reference text;

create index if not exists payroll_staff_payment_transactions_statement_date_idx
  on unimis.hrc_payroll_staff_payment_transactions(statement_id,payment_date desc,created_at desc);

create or replace function unimis.payroll_record_staff_payment_detailed(
  p_tenant uuid,
  p_statement uuid,
  p_amount numeric,
  p_reference text,
  p_payment_date date default current_date,
  p_method text default 'bank_transfer',
  p_notes text default null,
  p_batch_reference text default null
) returns jsonb
language plpgsql security definer set search_path=unimis as $$
declare s hrc_payroll_staff_statements%rowtype; np numeric; nb numeric;
begin
  if not unimis.has_tenant_role(p_tenant,array['owner','administrator','accountant','finance_manager','payroll_manager','payroll_officer']) then
    raise exception 'Payroll access denied';
  end if;
  select * into s from hrc_payroll_staff_statements where id=p_statement and tenant_id=p_tenant for update;
  if s.id is null then raise exception 'Staff payroll statement not found'; end if;
  if p_amount<=0 or p_amount>s.balance then raise exception 'Payment must be greater than zero and not exceed outstanding balance'; end if;
  if coalesce(trim(p_reference),'')='' then raise exception 'Payment reference is required'; end if;
  insert into hrc_payroll_staff_payment_transactions(tenant_id,statement_id,amount,payment_date,reference,payment_method,notes,batch_reference)
  values(p_tenant,p_statement,p_amount,coalesce(p_payment_date,current_date),trim(p_reference),coalesce(nullif(trim(p_method),''),'other'),nullif(trim(p_notes),''),nullif(trim(p_batch_reference),''));
  np:=s.amount_paid+p_amount; nb:=greatest(s.amount_due-np,0);
  update hrc_payroll_staff_statements set amount_paid=np,balance=nb,status=case when nb=0 then 'paid' else 'part_paid' end,last_payment_date=coalesce(p_payment_date,current_date),last_payment_reference=trim(p_reference),updated_at=now() where id=s.id;
  return jsonb_build_object('ok',true,'paid',np,'balance',nb,'statement_id',s.id);
end$$;
grant execute on function unimis.payroll_record_staff_payment_detailed(uuid,uuid,numeric,text,date,text,text,text) to authenticated;
notify pgrst,'reload schema';


-- SOURCE 202610220004_009h_professional_scoped_salary_increases.sql
-- 009h: professional scoped salary adjustments.
-- Adds auditable scope metadata and creates preview batches for an individual or selected employee category.
alter table unimis.hrc_payroll_salary_change_batches
  add column if not exists scope_type text,
  add column if not exists scope_value text,
  add column if not exists scope_label text;

alter table unimis.hrc_payroll_salary_change_batches drop constraint if exists payroll_salary_change_batches_change_mode_check;
alter table unimis.hrc_payroll_salary_change_batches add constraint payroll_salary_change_batches_change_mode_check
  check (change_mode in ('percentage','fixed','grade_step','manual','set_salary'));

create or replace function unimis.payroll_create_scoped_salary_batch(
 p_tenant uuid,p_scope text,p_scope_value text,p_mode text,p_value numeric,p_effective date,p_reason text default null
) returns jsonb language plpgsql security definer set search_path=unimis as $$
declare b uuid; bn text; r record; oldv numeric; newv numeric; n integer:=0; lbl text;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','payroll_manager','hr_manager']) then raise exception 'Salary change access denied'; end if;
 if p_scope not in ('employee','department','position','grade','employment_type','employment_status','all') then raise exception 'Invalid salary adjustment scope'; end if;
 if p_mode not in ('percentage','fixed','set_salary') then raise exception 'Invalid salary adjustment method'; end if;
 if coalesce(p_value,0)<=0 then raise exception 'Adjustment value must be greater than zero'; end if;
 if p_effective is null then raise exception 'Effective date is required'; end if;
 if p_scope<>'all' and nullif(trim(coalesce(p_scope_value,'')),'') is null then raise exception 'Select an employee/category'; end if;

 lbl:=case p_scope
  when 'all' then 'All active employees'
  when 'employee' then (select employee_no||' · '||first_name||' '||last_name from unimis.hrc_hr_employees where tenant_id=p_tenant and id=p_scope_value::uuid)
  when 'department' then (select name from unimis.hrc_departments where tenant_id=p_tenant and id=p_scope_value::uuid)
  when 'position' then (select title from unimis.hrc_hr_positions where tenant_id=p_tenant and id=p_scope_value::uuid)
  when 'grade' then (select code||' · '||name from unimis.hrc_hr_job_grades where tenant_id=p_tenant and id=p_scope_value::uuid)
  else initcap(replace(p_scope_value,'_',' ')) end;

 bn:='SAL-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS');
 insert into unimis.hrc_payroll_salary_change_batches(tenant_id,batch_no,change_mode,value,effective_date,reason,status,scope_type,scope_value,scope_label,created_by)
 values(p_tenant,bn,p_mode,p_value,p_effective,p_reason,'draft',p_scope,p_scope_value,lbl,auth.uid()) returning id into b;

 for r in
  select e.id
  from unimis.hrc_hr_employees e
  left join unimis.hrc_hr_positions pos on pos.id=e.position_id
  where e.tenant_id=p_tenant and e.employment_status='active'
   and case p_scope
    when 'all' then true
    when 'employee' then e.id=p_scope_value::uuid
    when 'department' then e.department_id=p_scope_value::uuid
    when 'position' then e.position_id=p_scope_value::uuid
    when 'grade' then pos.grade_id=p_scope_value::uuid
    when 'employment_type' then lower(coalesce(e.employment_type,''))=lower(p_scope_value)
    when 'employment_status' then lower(coalesce(e.employment_status,''))=lower(p_scope_value)
    else false end
 loop
  select coalesce(
   (select sh.new_salary from unimis.hrc_hr_salary_history sh where sh.employee_id=r.id and sh.effective_from<=p_effective order by sh.effective_from desc,sh.created_at desc limit 1),
   (select c.basic_salary from unimis.hrc_hr_employment_contracts c where c.employee_id=r.id and c.status='active' order by c.start_date desc limit 1),0) into oldv;
  newv:=case when p_mode='percentage' then round(oldv*(1+p_value/100),2) when p_mode='fixed' then round(oldv+p_value,2) when p_mode='set_salary' then round(p_value,2) else oldv end;
  insert into unimis.hrc_payroll_salary_change_items(tenant_id,batch_id,employee_id,old_salary,new_salary) values(p_tenant,b,r.id,oldv,newv);
  n:=n+1;
 end loop;
 if n=0 then delete from unimis.hrc_payroll_salary_change_batches where id=b; raise exception 'No active employees matched the selected category'; end if;
 return jsonb_build_object('batch_id',b,'affected',n,'scope',p_scope,'scope_label',lbl);
end $$;
grant execute on function unimis.payroll_create_scoped_salary_batch(uuid,text,text,text,numeric,date,text) to authenticated;
notify pgrst,'reload schema';




-- Refresh Supabase/PostgREST schema cache after this stage.
NOTIFY pgrst, 'reload schema';
