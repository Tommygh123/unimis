-- HRPayrollCore 007: Configurable Ghana statutory payroll engine (effective-dated; not hard-coded in UI)
-- Official seed basis: GRA 2026 PAYE effective 2026-09-01; SSNIT/NPRA 3-tier pension framework and 2026 insurable earnings.

alter table public.payroll_profiles
 add column if not exists tax_residency text not null default 'resident',
 add column if not exists pension_tier1_enabled boolean not null default true,
 add column if not exists pension_tier2_enabled boolean not null default true,
 add column if not exists provident_fund_enabled boolean not null default false,
 add column if not exists provident_employee_rate numeric(8,4) not null default 0,
 add column if not exists provident_employer_rate numeric(8,4) not null default 0,
 add column if not exists provident_scheme_name text;

alter table public.payroll_run_employees
 add column if not exists taxable_income numeric(14,2) not null default 0,
 add column if not exists chargeable_income numeric(14,2) not null default 0,
 add column if not exists tier1_total numeric(14,2) not null default 0,
 add column if not exists tier2_total numeric(14,2) not null default 0,
 add column if not exists provident_employee numeric(14,2) not null default 0,
 add column if not exists provident_employer numeric(14,2) not null default 0,
 add column if not exists tax_relief numeric(14,2) not null default 0,
 add column if not exists employer_cost numeric(14,2) not null default 0;

alter table public.payroll_components
 add column if not exists tax_treatment text not null default 'graduated',
 add column if not exists pre_tax boolean not null default false,
 add column if not exists recurring boolean not null default true;

create table if not exists public.payroll_tax_bands(
 id uuid primary key default gen_random_uuid(), tenant_id uuid references public.tenants(id) on delete cascade,
 country_code text not null default 'GH', tax_year int not null, frequency text not null default 'monthly',
 band_order int not null, band_amount numeric(14,2), rate numeric(8,4) not null,
 effective_from date not null, effective_to date, active boolean not null default true,
 source_note text, unique(tenant_id,country_code,frequency,effective_from,band_order)
);
create table if not exists public.payroll_pension_rules(
 id uuid primary key default gen_random_uuid(), tenant_id uuid references public.tenants(id) on delete cascade,
 country_code text not null default 'GH', name text not null, effective_from date not null, effective_to date,
 employee_rate numeric(8,4) not null default 0, employer_rate numeric(8,4) not null default 0,
 tier1_total_rate numeric(8,4) not null default 0, tier2_total_rate numeric(8,4) not null default 0,
 minimum_insurable numeric(14,2), maximum_insurable numeric(14,2), provident_tax_relief_cap_rate numeric(8,4) not null default 0,
 active boolean not null default true, source_note text, unique(tenant_id,country_code,effective_from)
);
create table if not exists public.payroll_relief_types(
 id uuid primary key default gen_random_uuid(), tenant_id uuid references public.tenants(id) on delete cascade,
 country_code text not null default 'GH', code text not null, name text not null, calculation_type text not null default 'fixed_annual',
 annual_amount numeric(14,2), percent_rate numeric(8,4), max_units int, requires_approval boolean not null default true,
 active boolean not null default true, source_note text, unique(tenant_id,country_code,code)
);
create table if not exists public.payroll_employee_reliefs(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 employee_id uuid not null references public.hr_employees(id) on delete cascade, relief_type_id uuid not null references public.payroll_relief_types(id),
 tax_year int not null, units int not null default 1, approved_annual_amount numeric(14,2), approved boolean not null default false,
 effective_from date not null, effective_to date, reference text, created_at timestamptz not null default now(),
 unique(employee_id,relief_type_id,tax_year)
);
create table if not exists public.payroll_adjustments(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 employee_id uuid not null references public.hr_employees(id) on delete cascade, period_id uuid references public.payroll_periods(id) on delete cascade,
 adjustment_type text not null check(adjustment_type in ('earning','deduction','pre_tax_deduction','loan','arrears','overtime','unpaid_absence','bonus')),
 code text not null, description text not null, amount numeric(14,2) not null, taxable boolean not null default true,
 pensionable boolean not null default false, status text not null default 'approved' check(status in ('draft','pending','approved','rejected')),
 source_module text, source_reference text, created_by uuid references auth.users(id), created_at timestamptz not null default now()
);
create table if not exists public.payroll_salary_change_batches(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 batch_no text not null, change_mode text not null check(change_mode in ('percentage','fixed','grade_step','manual')),
 value numeric(14,4), effective_date date not null, reason text, status text not null default 'draft' check(status in ('draft','approved','applied','cancelled')),
 created_by uuid references auth.users(id), approved_by uuid references auth.users(id), created_at timestamptz not null default now(), unique(tenant_id,batch_no)
);
create table if not exists public.payroll_salary_change_items(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 batch_id uuid not null references public.payroll_salary_change_batches(id) on delete cascade, employee_id uuid not null references public.hr_employees(id) on delete cascade,
 old_salary numeric(14,2) not null, new_salary numeric(14,2) not null, unique(batch_id,employee_id)
);

-- RLS
alter table public.payroll_tax_bands enable row level security; alter table public.payroll_pension_rules enable row level security;
alter table public.payroll_relief_types enable row level security; alter table public.payroll_employee_reliefs enable row level security;
alter table public.payroll_adjustments enable row level security; alter table public.payroll_salary_change_batches enable row level security; alter table public.payroll_salary_change_items enable row level security;
do $$ declare t text; begin
 foreach t in array array['payroll_tax_bands','payroll_pension_rules','payroll_relief_types'] loop
  execute format('create policy %I on public.%I for select to authenticated using (tenant_id is null or public.is_tenant_member(tenant_id))',t||'_read_007',t);
  execute format('create policy %I on public.%I for all to authenticated using (tenant_id is not null and public.has_tenant_role(tenant_id,array[''owner'',''administrator'',''payroll_manager''])) with check (tenant_id is not null and public.has_tenant_role(tenant_id,array[''owner'',''administrator'',''payroll_manager'']))',t||'_manage_007',t);
 end loop;
 foreach t in array array['payroll_employee_reliefs','payroll_adjustments','payroll_salary_change_batches','payroll_salary_change_items'] loop
  execute format('create policy %I on public.%I for select to authenticated using (public.is_tenant_member(tenant_id))',t||'_read_007',t);
  execute format('create policy %I on public.%I for all to authenticated using (public.has_tenant_role(tenant_id,array[''owner'',''administrator'',''payroll_manager'',''payroll_officer''])) with check (public.has_tenant_role(tenant_id,array[''owner'',''administrator'',''payroll_manager'',''payroll_officer'']))',t||'_manage_007',t);
 end loop;
end $$;

-- Official Ghana defaults are global templates (tenant_id NULL); tenants may clone/override later.
insert into public.payroll_tax_bands(tenant_id,country_code,tax_year,frequency,band_order,band_amount,rate,effective_from,source_note) values
(null,'GH',2026,'monthly',1,588,0,'2026-09-01','GRA Act 1178 / PAYE 2026'),
(null,'GH',2026,'monthly',2,80,5,'2026-09-01','GRA Act 1178 / PAYE 2026'),
(null,'GH',2026,'monthly',3,100,10,'2026-09-01','GRA Act 1178 / PAYE 2026'),
(null,'GH',2026,'monthly',4,2900,17.5,'2026-09-01','GRA Act 1178 / PAYE 2026'),
(null,'GH',2026,'monthly',5,16000,25,'2026-09-01','GRA Act 1178 / PAYE 2026'),
(null,'GH',2026,'monthly',6,30332,30,'2026-09-01','GRA Act 1178 / PAYE 2026'),
(null,'GH',2026,'monthly',7,null,35,'2026-09-01','GRA Act 1178 / PAYE 2026')
on conflict do nothing;
insert into public.payroll_pension_rules(tenant_id,country_code,name,effective_from,employee_rate,employer_rate,tier1_total_rate,tier2_total_rate,minimum_insurable,maximum_insurable,provident_tax_relief_cap_rate,source_note)
values(null,'GH','Ghana 3-Tier Pension 2026','2026-01-01',5.5,13,13.5,5,587.80,69000,16.5,'SSNIT/NPRA 2026') on conflict do nothing;
insert into public.payroll_relief_types(tenant_id,country_code,code,name,calculation_type,annual_amount,percent_rate,max_units,source_note) values
(null,'GH','MARRIAGE','Marriage / Responsibility','fixed_annual',1200,null,1,'GRA personal tax relief'),
(null,'GH','CHILD_EDU','Child Education','per_unit_annual',600,null,3,'GRA personal tax relief'),
(null,'GH','DISABILITY','Disability','percent_income',null,25,1,'GRA personal tax relief'),
(null,'GH','OLD_AGE','Old Age (60+)','fixed_annual',1500,null,1,'GRA personal tax relief'),
(null,'GH','AGED_DEP','Aged Dependent Relative','per_unit_annual',1000,null,2,'GRA personal tax relief'),
(null,'GH','EDUCATION','Professional / Technical Education','fixed_annual',2000,null,1,'GRA personal tax relief'),
(null,'GH','MORTGAGE','Qualifying Mortgage Interest','approved_amount',null,null,1,'GRA personal tax relief') on conflict do nothing;

create or replace function public.payroll_progressive_tax(p_tenant uuid,p_country text,p_date date,p_chargeable numeric)
returns numeric language plpgsql stable security definer set search_path=public as $$
declare rem numeric:=greatest(coalesce(p_chargeable,0),0); ans numeric:=0; b record; use_amt numeric;
begin
 for b in select * from public.payroll_tax_bands where country_code=p_country and active and effective_from<=p_date and (effective_to is null or effective_to>=p_date) and (tenant_id=p_tenant or tenant_id is null)
          order by (tenant_id is not null) desc, effective_from desc, band_order loop
  -- prefer one effective rule set; avoid mixing global and tenant overrides with same band order
  if exists(select 1 from public.payroll_tax_bands x where x.tenant_id=p_tenant and x.country_code=p_country and x.active and x.effective_from<=p_date and (x.effective_to is null or x.effective_to>=p_date)) and b.tenant_id is null then continue; end if;
  exit when rem<=0; use_amt:=case when b.band_amount is null then rem else least(rem,b.band_amount) end;
  ans:=ans+(use_amt*b.rate/100); rem:=rem-use_amt;
 end loop;
 return round(ans,2);
end $$;
grant execute on function public.payroll_progressive_tax(uuid,text,date,numeric) to authenticated;

create or replace function public.payroll_create_salary_batch(p_tenant uuid,p_mode text,p_value numeric,p_effective date,p_reason text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare b uuid; bn text; r record; oldv numeric; newv numeric;
begin
 if not public.has_tenant_role(p_tenant,array['owner','administrator','payroll_manager','hr_manager']) then raise exception 'Salary change access denied'; end if;
 bn:='SAL-'||to_char(now(),'YYYYMMDDHH24MISS'); insert into public.payroll_salary_change_batches(tenant_id,batch_no,change_mode,value,effective_date,reason,created_by) values(p_tenant,bn,p_mode,p_value,p_effective,p_reason,auth.uid()) returning id into b;
 for r in select e.id from public.hr_employees e where e.tenant_id=p_tenant and e.employment_status='active' loop
  select coalesce((select sh.new_salary from public.hr_salary_history sh where sh.employee_id=r.id and sh.effective_from<=p_effective order by sh.effective_from desc,sh.created_at desc limit 1),(select c.basic_salary from public.hr_employment_contracts c where c.employee_id=r.id and c.status='active' order by c.start_date desc limit 1),0) into oldv;
  newv:=case when p_mode='percentage' then round(oldv*(1+p_value/100),2) when p_mode='fixed' then round(oldv+p_value,2) else oldv end;
  insert into public.payroll_salary_change_items(tenant_id,batch_id,employee_id,old_salary,new_salary) values(p_tenant,b,r.id,oldv,newv);
 end loop; return b;
end $$;
grant execute on function public.payroll_create_salary_batch(uuid,text,numeric,date,text) to authenticated;

create or replace function public.payroll_apply_salary_batch(p_tenant uuid,p_batch uuid)
returns void language plpgsql security definer set search_path=public as $$
declare r record; d date; rs text;
begin
 if not public.has_tenant_role(p_tenant,array['owner','administrator','payroll_manager']) then raise exception 'Salary approval access denied'; end if;
 select effective_date,reason into d,rs from public.payroll_salary_change_batches where id=p_batch and tenant_id=p_tenant and status='draft'; if d is null then raise exception 'Draft batch not found'; end if;
 for r in select * from public.payroll_salary_change_items where batch_id=p_batch loop
  insert into public.hr_salary_history(tenant_id,employee_id,old_salary,new_salary,change_type,reason,effective_from,approved_by,created_by) values(p_tenant,r.employee_id,r.old_salary,r.new_salary,'bulk_adjustment',rs,d,auth.uid(),auth.uid());
  if d<=current_date then update public.hr_employment_contracts set basic_salary=r.new_salary where tenant_id=p_tenant and employee_id=r.employee_id and status='active'; end if;
 end loop;
 update public.payroll_salary_change_batches set status='applied',approved_by=auth.uid() where id=p_batch;
end $$;
grant execute on function public.payroll_apply_salary_batch(uuid,uuid) to authenticated;

-- Replace calculation engine: effective salary + configurable earnings/deductions + Ghana pension/PAYE + approved reliefs/adjustments.
create or replace function public.payroll_calculate_run(p_tenant uuid,p_period uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare r uuid; rn text; rec record; re uuid; pend date; country text; pr public.payroll_pension_rules%rowtype;
 basic numeric; earn numeric; ded numeric; taxable_extra numeric; pretax numeric; gross numeric; taxable numeric; insurable numeric; emp_pen numeric; er_pen numeric; tier1 numeric; tier2 numeric;
 pf_emp numeric; pf_er numeric; relief numeric; chargeable numeric; tx numeric; net numeric; adjearn numeric; adjded numeric; adjpretax numeric;
begin
 if not public.has_tenant_role(p_tenant,array['owner','administrator','payroll_manager','payroll_officer']) then raise exception 'Payroll access denied'; end if;
 select end_date into pend from public.payroll_periods where id=p_period and tenant_id=p_tenant; if pend is null then raise exception 'Invalid payroll period'; end if;
 select coalesce(country_code,'GH') into country from public.payroll_settings where tenant_id=p_tenant; country:=coalesce(country,'GH');
 select * into pr from public.payroll_pension_rules x where x.country_code=country and x.active and x.effective_from<=pend and (x.effective_to is null or x.effective_to>=pend) and (x.tenant_id=p_tenant or x.tenant_id is null) order by (x.tenant_id is not null) desc,x.effective_from desc limit 1;
 if country='GH' and not exists(select 1 from public.payroll_tax_bands b where b.country_code='GH' and b.active and b.effective_from<=pend and (b.effective_to is null or b.effective_to>=pend) and (b.tenant_id=p_tenant or b.tenant_id is null)) then raise exception 'No effective PAYE bands configured for payroll period end %',pend; end if;
 select id into r from public.payroll_runs where tenant_id=p_tenant and period_id=p_period;
 if r is null then rn:='RUN-'||to_char(pend,'YYYYMM')||'-'||lpad((1+(select count(*) from public.payroll_runs where tenant_id=p_tenant))::text,3,'0'); insert into public.payroll_runs(tenant_id,period_id,run_no,status,created_by) values(p_tenant,p_period,rn,'draft',auth.uid()) returning id into r;
 else if exists(select 1 from public.payroll_runs where id=r and status in ('approved','posted')) then raise exception 'Approved/posted payroll cannot be recalculated'; end if; delete from public.payroll_run_employees where run_id=r; end if;
 for rec in select e.*,pp.tax_residency,pp.pension_tier1_enabled,pp.pension_tier2_enabled,pp.provident_fund_enabled,pp.provident_employee_rate,pp.provident_employer_rate from public.hr_employees e join public.payroll_profiles pp on pp.employee_id=e.id and pp.active where e.tenant_id=p_tenant and e.employment_status='active' loop
  select coalesce((select sh.new_salary from public.hr_salary_history sh where sh.employee_id=rec.id and sh.effective_from<=pend order by sh.effective_from desc,sh.created_at desc limit 1),(select c.basic_salary from public.hr_employment_contracts c where c.employee_id=rec.id and c.status='active' order by c.start_date desc limit 1),0) into basic;
  select coalesce(sum(case when pc.component_type='earning' then pec.amount else 0 end),0),coalesce(sum(case when pc.component_type='deduction' then pec.amount else 0 end),0),coalesce(sum(case when pc.component_type='earning' and pc.taxable then pec.amount else 0 end),0),coalesce(sum(case when pc.component_type='deduction' and pc.pre_tax then pec.amount else 0 end),0) into earn,ded,taxable_extra,pretax from public.payroll_employee_components pec join public.payroll_components pc on pc.id=pec.component_id where pec.employee_id=rec.id and pec.tenant_id=p_tenant and pec.effective_from<=pend and (pec.effective_to is null or pec.effective_to>=pend) and pc.code<>'BASIC';
  select coalesce(sum(case when adjustment_type in ('earning','arrears','overtime','bonus') then amount else 0 end),0),coalesce(sum(case when adjustment_type in ('deduction','loan','unpaid_absence') then amount else 0 end),0),coalesce(sum(case when adjustment_type='pre_tax_deduction' then amount else 0 end),0) into adjearn,adjded,adjpretax from public.payroll_adjustments where tenant_id=p_tenant and employee_id=rec.id and period_id=p_period and status='approved';
  gross:=basic+earn+adjearn; taxable:=basic+taxable_extra+adjearn; insurable:=least(greatest(basic,coalesce(pr.minimum_insurable,0)),coalesce(pr.maximum_insurable,basic));
  emp_pen:=case when rec.pension_tier1_enabled then round(insurable*coalesce(pr.employee_rate,0)/100,2) else 0 end; er_pen:=case when rec.pension_tier1_enabled then round(insurable*coalesce(pr.employer_rate,0)/100,2) else 0 end;
  tier1:=case when rec.pension_tier1_enabled then round(insurable*coalesce(pr.tier1_total_rate,0)/100,2) else 0 end; tier2:=case when rec.pension_tier2_enabled then round(insurable*coalesce(pr.tier2_total_rate,0)/100,2) else 0 end;
  pf_emp:=case when rec.provident_fund_enabled then round(basic*coalesce(rec.provident_employee_rate,0)/100,2) else 0 end; pf_er:=case when rec.provident_fund_enabled then round(basic*coalesce(rec.provident_employer_rate,0)/100,2) else 0 end;
  select coalesce(sum(case when rt.calculation_type='percent_income' then taxable*coalesce(rt.percent_rate,0)/100 else coalesce(er.approved_annual_amount,case when rt.calculation_type='per_unit_annual' then rt.annual_amount*least(er.units,coalesce(rt.max_units,er.units)) else rt.annual_amount end,0) end)/12,0) into relief from public.payroll_employee_reliefs er join public.payroll_relief_types rt on rt.id=er.relief_type_id where er.tenant_id=p_tenant and er.employee_id=rec.id and er.approved and er.tax_year=extract(year from pend)::int and er.effective_from<=pend and (er.effective_to is null or er.effective_to>=pend);
  chargeable:=greatest(taxable-emp_pen-least(pf_emp+pf_er,basic*coalesce(pr.provident_tax_relief_cap_rate,0)/100)-pretax-adjpretax-relief,0);
  tx:=case when rec.tax_residency='non_resident' then round(chargeable*25/100,2) else public.payroll_progressive_tax(p_tenant,country,pend,chargeable) end;
  net:=gross-emp_pen-pf_emp-tx-ded-adjded-pretax-adjpretax;
  insert into public.payroll_run_employees(tenant_id,run_id,employee_id,employee_no,employee_name,basic_salary,other_earnings,gross_pay,employee_pension,employer_pension,tax,other_deductions,net_pay,taxable_income,chargeable_income,tier1_total,tier2_total,provident_employee,provident_employer,tax_relief,employer_cost) values(p_tenant,r,rec.id,rec.employee_no,concat_ws(' ',rec.first_name,rec.other_names,rec.last_name),basic,earn+adjearn,gross,emp_pen,er_pen,tx,ded+adjded+pretax+adjpretax,net,taxable,chargeable,tier1,tier2,pf_emp,pf_er,relief,gross+er_pen+pf_er) returning id into re;
  insert into public.payroll_run_items(tenant_id,run_employee_id,component_code,component_name,component_type,amount,taxable,pensionable) values(p_tenant,re,'BASIC','Basic Salary','earning',basic,true,true),(p_tenant,re,'SSNIT-EE','Employee SSNIT','deduction',emp_pen,false,false),(p_tenant,re,'PAYE','PAYE','deduction',tx,false,false);
  if pf_emp>0 then insert into public.payroll_run_items(tenant_id,run_employee_id,component_code,component_name,component_type,amount,taxable,pensionable) values(p_tenant,re,'TIER3-EE','Provident Fund Employee','deduction',pf_emp,false,false); end if;
 end loop;
 update public.payroll_runs prun set status='calculated',employee_count=x.cnt,gross_total=x.gross,deduction_total=x.ded,employee_pension_total=x.ep,employer_pension_total=x.erp,tax_total=x.tax,net_total=x.net from (select count(*) cnt,coalesce(sum(gross_pay),0) gross,coalesce(sum(other_deductions),0) ded,coalesce(sum(employee_pension),0) ep,coalesce(sum(employer_pension),0) erp,coalesce(sum(tax),0) tax,coalesce(sum(net_pay),0) net from public.payroll_run_employees where run_id=r)x where prun.id=r;
 update public.payroll_periods set status='review' where id=p_period; return r;
end $$;
grant execute on function public.payroll_calculate_run(uuid,uuid) to authenticated;

update public.payroll_settings set paye_enabled=true,employee_pension_rate=5.5,employer_pension_rate=13,statutory_note='Ghana statutory templates installed. Effective-dated rules apply; verify future amendments before production.' where country_code='GH';
