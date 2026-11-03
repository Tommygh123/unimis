-- HRPayrollCore 009f: repeatable complete demo seed for fresh local installations.
-- Runs only when an Owner/Administrator clicks Load complete demo data.
create or replace function public.seed_hrpayroll_demo(p_tenant uuid)
returns void language plpgsql security definer set search_path=public as $$
declare
 b uuid; le uuid; d1 uuid; d2 uuid; d3 uuid; g1 uuid; g2 uuid; p1 uuid; p2 uuid; p3 uuid; pg uuid;
 e1 uuid; e2 uuid; e3 uuid; e4 uuid; c uuid; rt uuid; per uuid; cyc uuid;
 mstart date:=date_trunc('month',current_date)::date; mend date:=(date_trunc('month',current_date)+interval '1 month - 1 day')::date;
begin
 if not public.has_tenant_role(p_tenant,array['owner','administrator']) then raise exception 'Owner/admin required'; end if;
 select id into b from public.branches where tenant_id=p_tenant order by created_at limit 1;
 if b is null then
   select id into le from public.legal_entities where tenant_id=p_tenant order by created_at limit 1;
   if le is null then insert into public.legal_entities(tenant_id,name) select p_tenant,name from public.tenants where id=p_tenant returning id into le; end if;
   insert into public.branches(tenant_id,legal_entity_id,code,name,city) values(p_tenant,le,'HQ','Head Office','Kumasi') returning id into b;
 end if;
 select id into pg from public.payroll_pay_groups where tenant_id=p_tenant and active order by created_at limit 1;
 if pg is null then insert into public.payroll_pay_groups(tenant_id,code,name,frequency) values(p_tenant,'MONTHLY','Monthly Payroll','monthly') returning id into pg; end if;

 insert into public.departments(tenant_id,branch_id,code,name) values
 (p_tenant,b,'ADM','Administration'),(p_tenant,b,'FIN','Finance'),(p_tenant,b,'OPS','Operations')
 on conflict(tenant_id,code) do update set name=excluded.name,branch_id=coalesce(public.departments.branch_id,excluded.branch_id);
 select id into d1 from public.departments where tenant_id=p_tenant and code='ADM'; select id into d2 from public.departments where tenant_id=p_tenant and code='FIN'; select id into d3 from public.departments where tenant_id=p_tenant and code='OPS';
 insert into public.hr_job_grades(tenant_id,code,name,min_salary,max_salary) values
 (p_tenant,'G1','Officer',2500,6000),(p_tenant,'G2','Senior Officer',4500,9000)
 on conflict(tenant_id,code) do update set name=excluded.name,min_salary=excluded.min_salary,max_salary=excluded.max_salary;
 select id into g1 from public.hr_job_grades where tenant_id=p_tenant and code='G1'; select id into g2 from public.hr_job_grades where tenant_id=p_tenant and code='G2';
 insert into public.hr_positions(tenant_id,department_id,grade_id,code,title) values
 (p_tenant,d1,g1,'ADMIN-OFF','Administrative Officer'),(p_tenant,d2,g2,'ACCT-OFF','Accounts Officer'),(p_tenant,d3,g1,'OPS-OFF','Operations Officer')
 on conflict(tenant_id,code) do update set title=excluded.title,department_id=excluded.department_id,grade_id=excluded.grade_id;
 select id into p1 from public.hr_positions where tenant_id=p_tenant and code='ADMIN-OFF'; select id into p2 from public.hr_positions where tenant_id=p_tenant and code='ACCT-OFF'; select id into p3 from public.hr_positions where tenant_id=p_tenant and code='OPS-OFF';

 insert into public.hr_employees(tenant_id,employee_no,first_name,last_name,email,branch_id,department_id,position_id,hire_date,employment_type,work_schedule,pension_status)
 values(p_tenant,'EMP001','Ama','Mensah','ama.mensah@example.test',b,d1,p1,current_date-500,'regular','full_time','active_contributor')
 on conflict(tenant_id,employee_no) do update set first_name='Ama',last_name='Mensah',department_id=d1,position_id=p1,employment_type='regular',employment_status='active' returning id into e1;
 if e1 is null then select id into e1 from public.hr_employees where tenant_id=p_tenant and employee_no='EMP001'; end if;
 insert into public.hr_employees(tenant_id,employee_no,first_name,last_name,email,branch_id,department_id,position_id,hire_date,employment_type,work_schedule,pension_status)
 values(p_tenant,'EMP002','Kwame','Asare','kwame.asare@example.test',b,d2,p2,current_date-420,'regular','full_time','active_contributor')
 on conflict(tenant_id,employee_no) do update set first_name='Kwame',last_name='Asare',department_id=d2,position_id=p2,employment_type='regular',employment_status='active' returning id into e2;
 if e2 is null then select id into e2 from public.hr_employees where tenant_id=p_tenant and employee_no='EMP002'; end if;
 insert into public.hr_employees(tenant_id,employee_no,first_name,last_name,email,branch_id,department_id,position_id,hire_date,employment_type,work_schedule,pension_status)
 values(p_tenant,'EMP003','Esi','Agyeman','esi.agyeman@example.test',b,d3,p3,current_date-180,'fixed_term','full_time','active_contributor')
 on conflict(tenant_id,employee_no) do update set first_name='Esi',last_name='Agyeman',department_id=d3,position_id=p3,employment_type='fixed_term',employment_status='active' returning id into e3;
 if e3 is null then select id into e3 from public.hr_employees where tenant_id=p_tenant and employee_no='EMP003'; end if;
 insert into public.hr_employees(tenant_id,employee_no,first_name,last_name,email,branch_id,department_id,position_id,hire_date,employment_type,work_schedule,pension_status)
 values(p_tenant,'EMP004','Kojo','Owusu','kojo.owusu@example.test',b,d3,p3,current_date-90,'casual','part_time','not_applicable')
 on conflict(tenant_id,employee_no) do update set first_name='Kojo',last_name='Owusu',department_id=d3,position_id=p3,employment_type='casual',employment_status='active' returning id into e4;
 if e4 is null then select id into e4 from public.hr_employees where tenant_id=p_tenant and employee_no='EMP004'; end if;

 -- Current contracts: do not duplicate on repeat runs.
 if not exists(select 1 from public.hr_employment_contracts where tenant_id=p_tenant and employee_id=e1 and status='active') then insert into public.hr_employment_contracts(tenant_id,employee_id,contract_type,start_date,basic_salary,pay_frequency,status) values(p_tenant,e1,'regular',current_date-500,4200,'monthly','active'); end if;
 if not exists(select 1 from public.hr_employment_contracts where tenant_id=p_tenant and employee_id=e2 and status='active') then insert into public.hr_employment_contracts(tenant_id,employee_id,contract_type,start_date,basic_salary,pay_frequency,status) values(p_tenant,e2,'regular',current_date-420,5000,'monthly','active'); end if;
 if not exists(select 1 from public.hr_employment_contracts where tenant_id=p_tenant and employee_id=e3 and status='active') then insert into public.hr_employment_contracts(tenant_id,employee_id,contract_type,start_date,end_date,basic_salary,pay_frequency,status) values(p_tenant,e3,'fixed_term',current_date-180,current_date+185,3200,'monthly','active'); end if;
 if not exists(select 1 from public.hr_employment_contracts where tenant_id=p_tenant and employee_id=e4 and status='active') then insert into public.hr_employment_contracts(tenant_id,employee_id,contract_type,start_date,basic_salary,pay_frequency,status) values(p_tenant,e4,'casual',current_date-90,1800,'monthly','active'); end if;

 insert into public.payroll_profiles(tenant_id,employee_id,pay_group_id,bank_name,bank_account_name,bank_account_number,payment_method,tier3_participation_mode,provident_fund_enabled,provident_employee_rate,provident_employer_rate,active) values
 (p_tenant,e1,pg,'Demo Bank','Ama Mensah','001000001','bank','participating',true,1,5,true),
 (p_tenant,e2,pg,'Demo Bank','Kwame Asare','001000002','bank','not_participating',false,0,0,true),
 (p_tenant,e3,pg,'Demo Bank','Esi Agyeman','001000003','bank','not_participating',false,0,0,true),
 (p_tenant,e4,pg,'Mobile Money','Kojo Owusu','0240000000','momo','not_participating',false,0,0,true)
 on conflict(tenant_id,employee_id) do update set pay_group_id=excluded.pay_group_id,bank_name=excluded.bank_name,bank_account_name=excluded.bank_account_name,bank_account_number=excluded.bank_account_number,payment_method=excluded.payment_method,active=true;

 insert into public.payroll_worker_classifications(tenant_id,employee_id,employment_relationship,tax_treatment,pension_status,tier3_participation,pay_frequency,effective_from,approved,approved_by,approved_at,reason)
 values
 (p_tenant,e1,'regular','standard_paye','active_contributor','participating','monthly',mstart,true,auth.uid(),now(),'009f demo'),
 (p_tenant,e2,'regular','standard_paye','active_contributor','not_participating','monthly',mstart,true,auth.uid(),now(),'009f demo'),
 (p_tenant,e3,'fixed_term','standard_paye','active_contributor','not_participating','monthly',mstart,true,auth.uid(),now(),'009f demo'),
 (p_tenant,e4,'casual','casual_worker','not_applicable','not_participating','monthly',mstart,true,auth.uid(),now(),'009f demo')
 on conflict(tenant_id,employee_id) where effective_to is null do update set employment_relationship=excluded.employment_relationship,tax_treatment=excluded.tax_treatment,pension_status=excluded.pension_status,tier3_participation=excluded.tier3_participation,pay_frequency=excluded.pay_frequency,approved=true,approved_by=auth.uid(),approved_at=now();

 -- Demo payroll catalogue and Ama's known recurring inputs.
 insert into public.payroll_components(tenant_id,code,name,component_type,taxable,pensionable,calculation_type,default_amount,tax_treatment,pre_tax,recurring,active,employee_or_employer,requires_consent,requires_approval,effective_from,description) values
 (p_tenant,'TRANSPORT','Transport Allowance','earning',true,false,'fixed',100,'graduated',false,true,true,'employee',false,true,mstart,'009f demo allowance'),
 (p_tenant,'CHILD_EDU_ALLOW','Child Education Allowance','earning',true,false,'fixed',10,'graduated',false,true,true,'employee',false,true,mstart,'009f demo allowance'),
 (p_tenant,'GARDEN_BOY','Garden Boy Allowance','earning',true,false,'fixed',10,'graduated',false,true,true,'employee',false,true,mstart,'009f demo allowance'),
 (p_tenant,'HOUSE_HELP','House Help Allowance','earning',true,false,'fixed',10,'graduated',false,true,true,'employee',false,true,mstart,'009f demo allowance'),
 (p_tenant,'STAFF_INS','Staff Insurance','deduction',false,false,'fixed',100,'post_tax',false,true,true,'employee',true,true,mstart,'009f demo deduction'),
 (p_tenant,'STAFF_TRANSPORT','Staff Transport','deduction',false,false,'fixed',20,'post_tax',false,true,true,'employee',true,true,mstart,'009f demo deduction')
 on conflict(tenant_id,code) do update set name=excluded.name,component_type=excluded.component_type,active=true;
 for c in select id from public.payroll_components where tenant_id=p_tenant and code in ('TRANSPORT','CHILD_EDU_ALLOW','GARDEN_BOY','HOUSE_HELP','STAFF_INS','STAFF_TRANSPORT') loop
   insert into public.payroll_employee_components(tenant_id,employee_id,component_id,amount,effective_from)
   select p_tenant,e1,c.id,case (select code from public.payroll_components where id=c.id) when 'TRANSPORT' then 100 when 'STAFF_INS' then 100 when 'STAFF_TRANSPORT' then 20 else 10 end,mstart
   on conflict(employee_id,component_id,effective_from) do update set amount=excluded.amount;
 end loop;

 insert into public.payroll_setup_configs(tenant_id,section,config) values(p_tenant,'tier3',jsonb_build_object('enabled',true,'participationMode','employee_opt_in','employeeRate',1,'employerRate',5,'basis','basic_salary','employeeRateMayVary',true,'employerRateMayVary',false))
 on conflict(tenant_id,section) do update set config=excluded.config,updated_at=now();

 select id into per from public.payroll_periods where tenant_id=p_tenant and start_date=mstart and end_date=mend order by created_at limit 1;
 if per is null then insert into public.payroll_periods(tenant_id,pay_group_id,name,start_date,end_date,pay_date,status) values(p_tenant,pg,to_char(mstart,'FMMonth YYYY'),mstart,mend,mend,'open') returning id into per; end if;
 -- Bonus 22 reproduces the known Ama test gross of 4,352 only if all four allowances are active; kept as a visible period input.
 if not exists(select 1 from public.payroll_adjustments where tenant_id=p_tenant and employee_id=e1 and period_id=per and source_reference='009F-BONUS-AMA') then
   insert into public.payroll_adjustments(tenant_id,employee_id,period_id,adjustment_type,code,description,amount,taxable,pensionable,status,source_module,source_reference,created_by) values(p_tenant,e1,per,'bonus','BONUS','Demo period bonus',22,true,false,'approved','demo','009F-BONUS-AMA',auth.uid());
 end if;

 select id into rt from public.payroll_relief_types where country_code='GH' and code='CHILD_EDU' and (tenant_id=p_tenant or tenant_id is null) order by (tenant_id is not null) desc limit 1;
 if rt is not null then
  insert into public.payroll_employee_reliefs(tenant_id,employee_id,relief_type_id,tax_year,units,approved_annual_amount,approved,effective_from,reference,relief_status,approval_date)
  values(p_tenant,e1,rt,extract(year from current_date)::int,1,50,true,date_trunc('year',current_date)::date,'009F-DEMO-RELIEF','active',current_date)
  on conflict(employee_id,relief_type_id,tax_year) do update set approved=true,approved_annual_amount=50,relief_status='active',approval_date=current_date;
 end if;

 -- Performance demo now seeds after employees exist (important on a fresh PC).
 if to_regclass('public.hr_performance_cycles') is not null then
   insert into public.hr_performance_cycles(tenant_id,name,cycle_type,start_date,end_date,status) values(p_tenant,extract(year from current_date)::text||' Annual Performance Review','annual',date_trunc('year',current_date)::date,(date_trunc('year',current_date)+interval '1 year - 1 day')::date,'open') on conflict do nothing;
 end if;
 insert into public.payroll_settings(tenant_id) values(p_tenant) on conflict(tenant_id) do nothing;
 insert into public.audit_events(tenant_id,actor_id,module,action,record_type,record_id,details) values(p_tenant,auth.uid(),'core','demo.seeded','tenant',p_tenant,jsonb_build_object('package','009f','employees',4,'repeatable',true));
end $$;
grant execute on function public.seed_hrpayroll_demo(uuid) to authenticated;
notify pgrst, 'reload schema';
