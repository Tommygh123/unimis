-- HRPayrollCore Package 002: operational HR + payroll core
-- Preserves all Package 001 data.

create table if not exists public.payroll_settings (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null unique references public.tenants(id) on delete cascade,
 country_code text not null default 'GH',
 currency text not null default 'GHS',
 employee_pension_rate numeric(8,5) not null default 0,
 employer_pension_rate numeric(8,5) not null default 0,
 paye_enabled boolean not null default false,
 statutory_note text not null default 'Configure and verify current statutory rates before production payroll.',
 updated_at timestamptz not null default now()
);

create table if not exists public.payroll_runs (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete cascade,
 period_id uuid not null references public.payroll_periods(id) on delete restrict,
 run_no text not null,
 status text not null default 'draft' check(status in ('draft','calculated','review','approved','posted','void')),
 gross_total numeric(14,2) not null default 0,
 deduction_total numeric(14,2) not null default 0,
 employee_pension_total numeric(14,2) not null default 0,
 employer_pension_total numeric(14,2) not null default 0,
 tax_total numeric(14,2) not null default 0,
 net_total numeric(14,2) not null default 0,
 employee_count integer not null default 0,
 created_by uuid references auth.users(id),
 approved_by uuid references auth.users(id),
 posted_by uuid references auth.users(id),
 created_at timestamptz not null default now(), approved_at timestamptz, posted_at timestamptz,
 unique(tenant_id,run_no), unique(tenant_id,period_id)
);

create table if not exists public.payroll_run_employees (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 run_id uuid not null references public.payroll_runs(id) on delete cascade,
 employee_id uuid not null references public.hr_employees(id) on delete restrict,
 employee_no text not null, employee_name text not null,
 basic_salary numeric(14,2) not null default 0, other_earnings numeric(14,2) not null default 0,
 gross_pay numeric(14,2) not null default 0, employee_pension numeric(14,2) not null default 0,
 employer_pension numeric(14,2) not null default 0, tax numeric(14,2) not null default 0,
 other_deductions numeric(14,2) not null default 0, net_pay numeric(14,2) not null default 0,
 created_at timestamptz not null default now(), unique(run_id,employee_id)
);

create table if not exists public.payroll_run_items (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 run_employee_id uuid not null references public.payroll_run_employees(id) on delete cascade,
 component_code text not null, component_name text not null, component_type text not null,
 amount numeric(14,2) not null default 0, taxable boolean not null default false, pensionable boolean not null default false
);

create table if not exists public.payroll_payslips (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 run_id uuid not null references public.payroll_runs(id) on delete cascade,
 run_employee_id uuid not null references public.payroll_run_employees(id) on delete cascade,
 employee_id uuid not null references public.hr_employees(id) on delete restrict,
 payslip_no text not null, issued_at timestamptz not null default now(), unique(tenant_id,payslip_no), unique(run_employee_id)
);

create table if not exists public.payroll_payment_batches (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 run_id uuid not null references public.payroll_runs(id) on delete restrict,
 batch_no text not null, payment_method text not null default 'bank', amount numeric(14,2) not null default 0,
 status text not null default 'draft' check(status in ('draft','ready','paid','cancelled')),
 created_by uuid references auth.users(id), created_at timestamptz not null default now(), paid_at timestamptz,
 unique(tenant_id,batch_no)
);

create index if not exists idx_payroll_runs_tenant on public.payroll_runs(tenant_id,created_at desc);
create index if not exists idx_run_employees_run on public.payroll_run_employees(run_id);
create index if not exists idx_payslips_employee on public.payroll_payslips(employee_id,issued_at desc);

alter table public.payroll_settings enable row level security;
alter table public.payroll_runs enable row level security;
alter table public.payroll_run_employees enable row level security;
alter table public.payroll_run_items enable row level security;
alter table public.payroll_payslips enable row level security;
alter table public.payroll_payment_batches enable row level security;

do $$ declare t text; begin
 foreach t in array array['payroll_settings','payroll_runs','payroll_run_employees','payroll_run_items','payroll_payslips','payroll_payment_batches'] loop
   execute format('create policy %I on public.%I for select using (public.is_tenant_member(tenant_id))', t||'_read_002', t);
 end loop;
end $$;
create policy "payroll settings managers" on public.payroll_settings for all
 using(public.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager']))
 with check(public.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager']));
create policy "payroll runs managers" on public.payroll_runs for all
 using(public.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager','payroll_officer','finance_manager']))
 with check(public.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager','payroll_officer','finance_manager']));
create policy "run employees managers" on public.payroll_run_employees for all
 using(public.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager','payroll_officer','finance_manager']))
 with check(public.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager','payroll_officer','finance_manager']));
create policy "run items managers" on public.payroll_run_items for all
 using(public.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager','payroll_officer','finance_manager']))
 with check(public.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager','payroll_officer','finance_manager']));
create policy "payslip managers" on public.payroll_payslips for all
 using(public.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager','payroll_officer','finance_manager']))
 with check(public.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager','payroll_officer','finance_manager']));
create policy "payment batch managers" on public.payroll_payment_batches for all
 using(public.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager','finance_manager']))
 with check(public.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager','finance_manager']));

-- Create one employee + contract + payroll profile atomically.
create or replace function public.hr_create_employee(
 p_tenant uuid,p_employee_no text,p_first_name text,p_last_name text,p_email text,
 p_department uuid,p_position uuid,p_hire_date date,p_basic_salary numeric
) returns uuid language plpgsql security definer set search_path=public as $$
declare e uuid; g uuid;
begin
 if not public.has_tenant_role(p_tenant,array['owner','administrator','hr_manager','hr_officer']) then raise exception 'HR access denied'; end if;
 insert into public.hr_employees(tenant_id,employee_no,first_name,last_name,email,department_id,position_id,hire_date)
 values(p_tenant,upper(trim(p_employee_no)),trim(p_first_name),trim(p_last_name),nullif(trim(p_email),''),p_department,p_position,p_hire_date)
 returning id into e;
 insert into public.hr_employment_contracts(tenant_id,employee_id,start_date,basic_salary)
 values(p_tenant,e,coalesce(p_hire_date,current_date),coalesce(p_basic_salary,0));
 select id into g from public.payroll_pay_groups where tenant_id=p_tenant and active order by created_at limit 1;
 insert into public.payroll_profiles(tenant_id,employee_id,pay_group_id) values(p_tenant,e,g);
 insert into public.audit_events(tenant_id,actor_id,module,action,record_type,record_id)
 values(p_tenant,auth.uid(),'hr','employee.created','employee',e);
 return e;
end $$;
grant execute on function public.hr_create_employee(uuid,text,text,text,text,uuid,uuid,date,numeric) to authenticated;

-- Calculate a payroll run. Statutory percentages are tenant-configurable and default to zero until verified.
create or replace function public.payroll_calculate_run(p_tenant uuid,p_period uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare r uuid; rn text; s public.payroll_settings%rowtype; rec record; re uuid;
        basic numeric; earn numeric; ded numeric; gross numeric; ep numeric; erp numeric; tx numeric; net numeric;
begin
 if not public.has_tenant_role(p_tenant,array['owner','administrator','payroll_manager','payroll_officer']) then raise exception 'Payroll access denied'; end if;
 if not exists(select 1 from public.payroll_periods where id=p_period and tenant_id=p_tenant) then raise exception 'Invalid payroll period'; end if;
 insert into public.payroll_settings(tenant_id) values(p_tenant) on conflict(tenant_id) do nothing;
 select * into s from public.payroll_settings where tenant_id=p_tenant;
 select id into r from public.payroll_runs where tenant_id=p_tenant and period_id=p_period;
 if r is null then
   rn:='RUN-'||to_char(current_date,'YYYYMM')||'-'||lpad((1+(select count(*) from public.payroll_runs where tenant_id=p_tenant))::text,3,'0');
   insert into public.payroll_runs(tenant_id,period_id,run_no,status,created_by) values(p_tenant,p_period,rn,'draft',auth.uid()) returning id into r;
 else
   if exists(select 1 from public.payroll_runs where id=r and status in ('approved','posted')) then raise exception 'Approved/posted payroll cannot be recalculated'; end if;
   delete from public.payroll_run_employees where run_id=r; update public.payroll_runs set status='draft' where id=r;
 end if;
 for rec in select e.* from public.hr_employees e join public.payroll_profiles pp on pp.employee_id=e.id and pp.active
            where e.tenant_id=p_tenant and e.employment_status='active' loop
   select coalesce(c.basic_salary,0) into basic from public.hr_employment_contracts c where c.employee_id=rec.id and c.status='active' order by c.start_date desc limit 1;
   select coalesce(sum(pec.amount) filter (where pc.component_type='earning'),0), coalesce(sum(pec.amount) filter (where pc.component_type='deduction'),0)
     into earn,ded from public.payroll_employee_components pec join public.payroll_components pc on pc.id=pec.component_id
     where pec.employee_id=rec.id and pec.tenant_id=p_tenant and pec.effective_from <= current_date and (pec.effective_to is null or pec.effective_to>=current_date) and pc.code<>'BASIC';
   earn:=coalesce(earn,0); ded:=coalesce(ded,0); gross:=basic+earn;
   ep:=round(gross*s.employee_pension_rate/100,2); erp:=round(gross*s.employer_pension_rate/100,2);
   tx:=0; -- PAYE engine remains disabled until verified statutory bands are configured.
   net:=gross-ep-tx-ded;
   insert into public.payroll_run_employees(tenant_id,run_id,employee_id,employee_no,employee_name,basic_salary,other_earnings,gross_pay,employee_pension,employer_pension,tax,other_deductions,net_pay)
   values(p_tenant,r,rec.id,rec.employee_no,concat_ws(' ',rec.first_name,rec.other_names,rec.last_name),basic,earn,gross,ep,erp,tx,ded,net) returning id into re;
   insert into public.payroll_run_items(tenant_id,run_employee_id,component_code,component_name,component_type,amount,taxable,pensionable)
   values(p_tenant,re,'BASIC','Basic Salary','earning',basic,true,true);
   insert into public.payroll_run_items(tenant_id,run_employee_id,component_code,component_name,component_type,amount,taxable,pensionable)
   select p_tenant,re,pc.code,pc.name,pc.component_type,pec.amount,pc.taxable,pc.pensionable
   from public.payroll_employee_components pec join public.payroll_components pc on pc.id=pec.component_id
   where pec.employee_id=rec.id and pec.tenant_id=p_tenant and pc.code<>'BASIC' and pec.effective_from<=current_date and (pec.effective_to is null or pec.effective_to>=current_date);
 end loop;
 update public.payroll_runs pr set status='calculated', employee_count=x.cnt,gross_total=x.gross,deduction_total=x.ded,
 employee_pension_total=x.ep,employer_pension_total=x.erp,tax_total=x.tax,net_total=x.net
 from (select count(*) cnt,coalesce(sum(gross_pay),0) gross,coalesce(sum(other_deductions),0) ded,coalesce(sum(employee_pension),0) ep,
 coalesce(sum(employer_pension),0) erp,coalesce(sum(tax),0) tax,coalesce(sum(net_pay),0) net from public.payroll_run_employees where run_id=r) x where pr.id=r;
 update public.payroll_periods set status='review' where id=p_period;
 insert into public.audit_events(tenant_id,actor_id,module,action,record_type,record_id) values(p_tenant,auth.uid(),'payroll','run.calculated','payroll_run',r);
 return r;
end $$;
grant execute on function public.payroll_calculate_run(uuid,uuid) to authenticated;

create or replace function public.payroll_approve_run(p_tenant uuid,p_run uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.has_tenant_role(p_tenant,array['owner','administrator','payroll_manager','approver']) then raise exception 'Approval access denied'; end if;
 update public.payroll_runs set status='approved',approved_by=auth.uid(),approved_at=now() where id=p_run and tenant_id=p_tenant and status in ('calculated','review');
 if not found then raise exception 'Payroll run is not ready for approval'; end if;
 update public.payroll_periods set status='approved' where id=(select period_id from public.payroll_runs where id=p_run);
 insert into public.audit_events(tenant_id,actor_id,module,action,record_type,record_id) values(p_tenant,auth.uid(),'payroll','run.approved','payroll_run',p_run);
end $$;
grant execute on function public.payroll_approve_run(uuid,uuid) to authenticated;

create or replace function public.payroll_post_run(p_tenant uuid,p_run uuid)
returns void language plpgsql security definer set search_path=public as $$
declare rr record; n integer:=0;
begin
 if not public.has_tenant_role(p_tenant,array['owner','administrator','payroll_manager','finance_manager']) then raise exception 'Posting access denied'; end if;
 if not exists(select 1 from public.payroll_runs where id=p_run and tenant_id=p_tenant and status='approved') then raise exception 'Only approved payroll can be posted'; end if;
 for rr in select * from public.payroll_run_employees where run_id=p_run loop
   n:=n+1;
   insert into public.payroll_payslips(tenant_id,run_id,run_employee_id,employee_id,payslip_no)
   values(p_tenant,p_run,rr.id,rr.employee_id,'PS-'||to_char(current_date,'YYYYMM')||'-'||lpad(n::text,4,'0')) on conflict(run_employee_id) do nothing;
 end loop;
 update public.payroll_runs set status='posted',posted_by=auth.uid(),posted_at=now() where id=p_run;
 update public.payroll_periods set status='posted' where id=(select period_id from public.payroll_runs where id=p_run);
 insert into public.payroll_payment_batches(tenant_id,run_id,batch_no,amount,created_by)
 select p_tenant,p_run,'PB-'||to_char(current_date,'YYYYMMDD')||'-'||substr(p_run::text,1,6),net_total,auth.uid() from public.payroll_runs where id=p_run
 on conflict(tenant_id,batch_no) do nothing;
 insert into public.audit_events(tenant_id,actor_id,module,action,record_type,record_id) values(p_tenant,auth.uid(),'payroll','run.posted','payroll_run',p_run);
end $$;
grant execute on function public.payroll_post_run(uuid,uuid) to authenticated;

-- Optional demo data for testing. It never runs automatically.
create or replace function public.seed_hrpayroll_demo(p_tenant uuid)
returns void language plpgsql security definer set search_path=public as $$
declare b uuid; d1 uuid; d2 uuid; g1 uuid; p1 uuid; p2 uuid; pg uuid; e uuid; i int;
begin
 if not public.has_tenant_role(p_tenant,array['owner','administrator']) then raise exception 'Owner/admin required'; end if;
 select id into b from public.branches where tenant_id=p_tenant order by created_at limit 1;
 insert into public.departments(tenant_id,branch_id,code,name) values(p_tenant,b,'ADM','Administration') on conflict(tenant_id,code) do update set name=excluded.name returning id into d1;
 insert into public.departments(tenant_id,branch_id,code,name) values(p_tenant,b,'FIN','Finance') on conflict(tenant_id,code) do update set name=excluded.name returning id into d2;
 insert into public.hr_job_grades(tenant_id,code,name,min_salary,max_salary) values(p_tenant,'G1','Officer',2500,6000) on conflict(tenant_id,code) do update set name=excluded.name returning id into g1;
 insert into public.hr_positions(tenant_id,department_id,grade_id,code,title) values(p_tenant,d1,g1,'ADMIN-OFF','Administrative Officer') on conflict(tenant_id,code) do update set title=excluded.title returning id into p1;
 insert into public.hr_positions(tenant_id,department_id,grade_id,code,title) values(p_tenant,d2,g1,'ACCT-OFF','Accounts Officer') on conflict(tenant_id,code) do update set title=excluded.title returning id into p2;
 select id into pg from public.payroll_pay_groups where tenant_id=p_tenant order by created_at limit 1;
 if not exists(select 1 from public.hr_employees where tenant_id=p_tenant and employee_no='EMP001') then
  insert into public.hr_employees(tenant_id,employee_no,first_name,last_name,email,branch_id,department_id,position_id,hire_date) values(p_tenant,'EMP001','Ama','Mensah','ama.mensah@example.test',b,d1,p1,current_date-500) returning id into e;
  insert into public.hr_employment_contracts(tenant_id,employee_id,start_date,basic_salary) values(p_tenant,e,current_date-500,4200);
  insert into public.payroll_profiles(tenant_id,employee_id,pay_group_id,bank_name,payment_method) values(p_tenant,e,pg,'Demo Bank','bank');
 end if;
 if not exists(select 1 from public.hr_employees where tenant_id=p_tenant and employee_no='EMP002') then
  insert into public.hr_employees(tenant_id,employee_no,first_name,last_name,email,branch_id,department_id,position_id,hire_date) values(p_tenant,'EMP002','Kwame','Asare','kwame.asare@example.test',b,d2,p2,current_date-420) returning id into e;
  insert into public.hr_employment_contracts(tenant_id,employee_id,start_date,basic_salary) values(p_tenant,e,current_date-420,5000);
  insert into public.payroll_profiles(tenant_id,employee_id,pay_group_id,bank_name,payment_method) values(p_tenant,e,pg,'Demo Bank','bank');
 end if;
 if not exists(select 1 from public.payroll_periods where tenant_id=p_tenant and name=to_char(current_date,'FMMonth YYYY')) then
  insert into public.payroll_periods(tenant_id,pay_group_id,name,start_date,end_date,pay_date)
  values(p_tenant,pg,to_char(current_date,'FMMonth YYYY'),date_trunc('month',current_date)::date,(date_trunc('month',current_date)+interval '1 month - 1 day')::date,(date_trunc('month',current_date)+interval '1 month - 1 day')::date);
 end if;
 insert into public.payroll_settings(tenant_id) values(p_tenant) on conflict(tenant_id) do nothing;
 insert into public.audit_events(tenant_id,actor_id,module,action,record_type,record_id,details) values(p_tenant,auth.uid(),'core','demo.seeded','tenant',p_tenant,jsonb_build_object('package','002'));
end $$;
grant execute on function public.seed_hrpayroll_demo(uuid) to authenticated;

notify pgrst, 'reload schema';
