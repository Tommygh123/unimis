-- UniMIS Build 174: HR/Payroll realistic test seed
-- Shared remote test DB only. Restricted to Union Technical University.
set search_path=unimis,public;

do $$
declare v_tenant uuid := 'e21a0228-f0d5-4e72-9b29-30936ce453de';
begin
 if not exists(select 1 from unimis.hrc_tenants t where t.id=v_tenant) then
   raise exception 'Open HR once as the Union Technical University Owner before seeding.';
 end if;
end $$;

insert into unimis.hrc_branches(id,tenant_id,code,name,city,active) values
('17400000-0000-4000-8000-000000000001','e21a0228-f0d5-4e72-9b29-30936ce453de','MAIN','Main Campus','Kumasi',true)
on conflict(id) do update set name=excluded.name,city=excluded.city,active=true;

insert into unimis.hrc_departments(id,tenant_id,branch_id,code,name,active) values
('17410000-0000-4000-8000-000000000001','e21a0228-f0d5-4e72-9b29-30936ce453de','17400000-0000-4000-8000-000000000001','ADM','Administration',true),
('17410000-0000-4000-8000-000000000002','e21a0228-f0d5-4e72-9b29-30936ce453de','17400000-0000-4000-8000-000000000001','FIN','Finance',true),
('17410000-0000-4000-8000-000000000003','e21a0228-f0d5-4e72-9b29-30936ce453de','17400000-0000-4000-8000-000000000001','REG','Registry',true),
('17410000-0000-4000-8000-000000000004','e21a0228-f0d5-4e72-9b29-30936ce453de','17400000-0000-4000-8000-000000000001','ICT','ICT',true),
('17410000-0000-4000-8000-000000000005','e21a0228-f0d5-4e72-9b29-30936ce453de','17400000-0000-4000-8000-000000000001','ENG','Engineering',true),
('17410000-0000-4000-8000-000000000006','e21a0228-f0d5-4e72-9b29-30936ce453de','17400000-0000-4000-8000-000000000001','BUS','Business',true),
('17410000-0000-4000-8000-000000000007','e21a0228-f0d5-4e72-9b29-30936ce453de','17400000-0000-4000-8000-000000000001','LIB','Library',true)
on conflict(id) do update set name=excluded.name,active=true;

insert into unimis.hrc_hr_job_grades(id,tenant_id,code,name,min_salary,max_salary) values
('17420000-0000-4000-8000-000000000001','e21a0228-f0d5-4e72-9b29-30936ce453de','G01','Support',1800,3200),
('17420000-0000-4000-8000-000000000002','e21a0228-f0d5-4e72-9b29-30936ce453de','G02','Technical / Administrative',3000,5500),
('17420000-0000-4000-8000-000000000003','e21a0228-f0d5-4e72-9b29-30936ce453de','G03','Professional',5000,8500),
('17420000-0000-4000-8000-000000000004','e21a0228-f0d5-4e72-9b29-30936ce453de','G04','Senior Professional',8000,13000),
('17420000-0000-4000-8000-000000000005','e21a0228-f0d5-4e72-9b29-30936ce453de','G05','Management',12000,20000)
on conflict(id) do update set name=excluded.name,min_salary=excluded.min_salary,max_salary=excluded.max_salary;

insert into unimis.hrc_hr_positions(id,tenant_id,department_id,grade_id,code,title,active) values
('17430000-0000-4000-8000-000000000001','e21a0228-f0d5-4e72-9b29-30936ce453de','17410000-0000-4000-8000-000000000003','17420000-0000-4000-8000-000000000005','REGISTRAR','Registrar',true),
('17430000-0000-4000-8000-000000000002','e21a0228-f0d5-4e72-9b29-30936ce453de','17410000-0000-4000-8000-000000000002','17420000-0000-4000-8000-000000000004','ACCOUNTANT','Accountant',true),
('17430000-0000-4000-8000-000000000003','e21a0228-f0d5-4e72-9b29-30936ce453de','17410000-0000-4000-8000-000000000004','17420000-0000-4000-8000-000000000004','ICTMGR','ICT Manager',true),
('17430000-0000-4000-8000-000000000004','e21a0228-f0d5-4e72-9b29-30936ce453de','17410000-0000-4000-8000-000000000005','17420000-0000-4000-8000-000000000004','SLECT','Senior Lecturer',true),
('17430000-0000-4000-8000-000000000005','e21a0228-f0d5-4e72-9b29-30936ce453de','17410000-0000-4000-8000-000000000005','17420000-0000-4000-8000-000000000003','LECT','Lecturer',true),
('17430000-0000-4000-8000-000000000006','e21a0228-f0d5-4e72-9b29-30936ce453de','17410000-0000-4000-8000-000000000005','17420000-0000-4000-8000-000000000002','TECH','Laboratory Technician',true),
('17430000-0000-4000-8000-000000000007','e21a0228-f0d5-4e72-9b29-30936ce453de','17410000-0000-4000-8000-000000000001','17420000-0000-4000-8000-000000000002','ADMINOFF','Administrative Officer',true),
('17430000-0000-4000-8000-000000000008','e21a0228-f0d5-4e72-9b29-30936ce453de','17410000-0000-4000-8000-000000000007','17420000-0000-4000-8000-000000000003','LIBRARIAN','Librarian',true)
on conflict(id) do update set title=excluded.title,active=true;

insert into unimis.hrc_hr_employees(id,tenant_id,employee_no,first_name,last_name,email,phone,branch_id,department_id,position_id,hire_date,employment_status) values
('17440000-0000-4000-8000-000000000001','e21a0228-f0d5-4e72-9b29-30936ce453de','UTU001','Kwame','Mensah','kwame.mensah@utu.test','0240000001','17400000-0000-4000-8000-000000000001','17410000-0000-4000-8000-000000000003','17430000-0000-4000-8000-000000000001','2020-01-06','active'),
('17440000-0000-4000-8000-000000000002','e21a0228-f0d5-4e72-9b29-30936ce453de','UTU002','Akosua','Owusu','akosua.owusu@utu.test','0240000002','17400000-0000-4000-8000-000000000001','17410000-0000-4000-8000-000000000002','17430000-0000-4000-8000-000000000002','2021-03-01','active'),
('17440000-0000-4000-8000-000000000003','e21a0228-f0d5-4e72-9b29-30936ce453de','UTU003','Kojo','Asante','kojo.asante@utu.test','0240000003','17400000-0000-4000-8000-000000000001','17410000-0000-4000-8000-000000000004','17430000-0000-4000-8000-000000000003','2022-02-14','active'),
('17440000-0000-4000-8000-000000000004','e21a0228-f0d5-4e72-9b29-30936ce453de','UTU004','Ama','Boateng','ama.boateng@utu.test','0240000004','17400000-0000-4000-8000-000000000001','17410000-0000-4000-8000-000000000005','17430000-0000-4000-8000-000000000004','2019-08-12','active'),
('17440000-0000-4000-8000-000000000005','e21a0228-f0d5-4e72-9b29-30936ce453de','UTU005','Yaw','Osei','yaw.osei@utu.test','0240000005','17400000-0000-4000-8000-000000000001','17410000-0000-4000-8000-000000000005','17430000-0000-4000-8000-000000000005','2023-01-09','active'),
('17440000-0000-4000-8000-000000000006','e21a0228-f0d5-4e72-9b29-30936ce453de','UTU006','Adwoa','Frimpong','adwoa.frimpong@utu.test','0240000006','17400000-0000-4000-8000-000000000001','17410000-0000-4000-8000-000000000005','17430000-0000-4000-8000-000000000005','2024-01-15','active'),
('17440000-0000-4000-8000-000000000007','e21a0228-f0d5-4e72-9b29-30936ce453de','UTU007','Kofi','Agyeman','kofi.agyeman@utu.test','0240000007','17400000-0000-4000-8000-000000000001','17410000-0000-4000-8000-000000000005','17430000-0000-4000-8000-000000000006','2022-09-05','active'),
('17440000-0000-4000-8000-000000000008','e21a0228-f0d5-4e72-9b29-30936ce453de','UTU008','Abena','Sarpong','abena.sarpong@utu.test','0240000008','17400000-0000-4000-8000-000000000001','17410000-0000-4000-8000-000000000001','17430000-0000-4000-8000-000000000007','2023-05-02','active'),
('17440000-0000-4000-8000-000000000009','e21a0228-f0d5-4e72-9b29-30936ce453de','UTU009','Nana','Darko','nana.darko@utu.test','0240000009','17400000-0000-4000-8000-000000000001','17410000-0000-4000-8000-000000000007','17430000-0000-4000-8000-000000000008','2021-10-04','active'),
('17440000-0000-4000-8000-000000000010','e21a0228-f0d5-4e72-9b29-30936ce453de','UTU010','Efua','Nyarko','efua.nyarko@utu.test','0240000010','17400000-0000-4000-8000-000000000001','17410000-0000-4000-8000-000000000006',null,'2024-06-03','active')
on conflict(id) do update set first_name=excluded.first_name,last_name=excluded.last_name,email=excluded.email,department_id=excluded.department_id,position_id=excluded.position_id,employment_status='active';

insert into unimis.hrc_hr_leave_types(id,tenant_id,code,name,default_days,paid,active) values
('17450000-0000-4000-8000-000000000001','e21a0228-f0d5-4e72-9b29-30936ce453de','ANNUAL','Annual Leave',21,true,true),
('17450000-0000-4000-8000-000000000002','e21a0228-f0d5-4e72-9b29-30936ce453de','SICK','Sick Leave',10,true,true)
on conflict(id) do update set name=excluded.name,default_days=excluded.default_days,active=true;

insert into unimis.hrc_hr_leave_requests(id,tenant_id,employee_id,leave_type_id,start_date,end_date,reason,status) values
('17451000-0000-4000-8000-000000000001','e21a0228-f0d5-4e72-9b29-30936ce453de','17440000-0000-4000-8000-000000000005','17450000-0000-4000-8000-000000000001','2026-11-09','2026-11-13','Family travel','submitted'),
('17451000-0000-4000-8000-000000000002','e21a0228-f0d5-4e72-9b29-30936ce453de','17440000-0000-4000-8000-000000000008','17450000-0000-4000-8000-000000000002','2026-10-19','2026-10-20','Medical rest','approved')
on conflict(id) do nothing;

insert into unimis.hrc_hr_attendance_records(id,tenant_id,employee_id,work_date,check_in,check_out,status,capture_method,late_minutes,worked_minutes) values
('17460000-0000-4000-8000-000000000001','e21a0228-f0d5-4e72-9b29-30936ce453de','17440000-0000-4000-8000-000000000004','2026-11-02','2026-11-02 07:52+00','2026-11-02 16:10+00','present','import',0,498),
('17460000-0000-4000-8000-000000000002','e21a0228-f0d5-4e72-9b29-30936ce453de','17440000-0000-4000-8000-000000000005','2026-11-02','2026-11-02 08:17+00','2026-11-02 16:04+00','late','import',17,467),
('17460000-0000-4000-8000-000000000003','e21a0228-f0d5-4e72-9b29-30936ce453de','17440000-0000-4000-8000-000000000007','2026-11-02',null,null,'absent','import',0,0),
('17460000-0000-4000-8000-000000000004','e21a0228-f0d5-4e72-9b29-30936ce453de','17440000-0000-4000-8000-000000000002','2026-11-03','2026-11-03 07:58+00',null,'present','import',0,0)
on conflict(id) do nothing;

insert into unimis.hrc_hr_performance_cycles(id,tenant_id,name,cycle_type,start_date,end_date,status) values
('17470000-0000-4000-8000-000000000001','e21a0228-f0d5-4e72-9b29-30936ce453de','2026 Annual Performance Cycle','annual','2026-01-01','2026-12-31','open')
on conflict(id) do update set status='open';

insert into unimis.hrc_payroll_pay_groups(id,tenant_id,code,name,frequency,active) values
('17480000-0000-4000-8000-000000000001','e21a0228-f0d5-4e72-9b29-30936ce453de','MONTHLY','Monthly Staff','monthly',true)
on conflict(id) do update set active=true;

insert into unimis.hrc_payroll_components(id,tenant_id,code,name,component_type,taxable,pensionable,calculation_type,default_amount,active) values
('17481000-0000-4000-8000-000000000001','e21a0228-f0d5-4e72-9b29-30936ce453de','BASIC','Basic Salary','earning',true,true,'fixed',0,true),
('17481000-0000-4000-8000-000000000002','e21a0228-f0d5-4e72-9b29-30936ce453de','TRANSPORT','Transport Allowance','earning',true,false,'fixed',500,true),
('17481000-0000-4000-8000-000000000003','e21a0228-f0d5-4e72-9b29-30936ce453de','WELFARE','Staff Welfare','deduction',false,false,'fixed',100,true)
on conflict(id) do update set name=excluded.name,default_amount=excluded.default_amount,active=true;

insert into unimis.hrc_payroll_periods(id,tenant_id,pay_group_id,name,start_date,end_date,pay_date,status) values
('17482000-0000-4000-8000-000000000001','e21a0228-f0d5-4e72-9b29-30936ce453de','17480000-0000-4000-8000-000000000001','October 2026','2026-10-01','2026-10-31','2026-10-30','closed'),
('17482000-0000-4000-8000-000000000002','e21a0228-f0d5-4e72-9b29-30936ce453de','17480000-0000-4000-8000-000000000001','November 2026','2026-11-01','2026-11-30','2026-11-30','open')
on conflict(id) do update set status=excluded.status;

insert into unimis.hrc_payroll_runs(id,tenant_id,period_id,run_no,status,gross_total,deduction_total,employee_pension_total,employer_pension_total,tax_total,net_total,employee_count) values
('17483000-0000-4000-8000-000000000001','e21a0228-f0d5-4e72-9b29-30936ce453de','17482000-0000-4000-8000-000000000001','PR-2026-10','posted',72500,11150,3987.50,9425,4962.50,61350,10)
on conflict(id) do update set gross_total=excluded.gross_total,net_total=excluded.net_total,employee_count=excluded.employee_count;

insert into unimis.hrc_payroll_run_employees(id,tenant_id,run_id,employee_id,employee_no,employee_name,basic_salary,other_earnings,gross_pay,employee_pension,employer_pension,tax,other_deductions,net_pay) values
('17484000-0000-4000-8000-000000000001','e21a0228-f0d5-4e72-9b29-30936ce453de','17483000-0000-4000-8000-000000000001','17440000-0000-4000-8000-000000000001','UTU001','Kwame Mensah',12500,500,13000,687.50,1625,1250,100,10962.50),
('17484000-0000-4000-8000-000000000002','e21a0228-f0d5-4e72-9b29-30936ce453de','17483000-0000-4000-8000-000000000001','17440000-0000-4000-8000-000000000002','UTU002','Akosua Owusu',8500,500,9000,467.50,1105,650,100,7782.50),
('17484000-0000-4000-8000-000000000003','e21a0228-f0d5-4e72-9b29-30936ce453de','17483000-0000-4000-8000-000000000001','17440000-0000-4000-8000-000000000004','UTU004','Ama Boateng',9500,500,10000,522.50,1235,800,100,8577.50)
on conflict(id) do nothing;

insert into unimis.hrc_payroll_payslips(id,tenant_id,run_id,run_employee_id,employee_id,payslip_no) values
('17485000-0000-4000-8000-000000000001','e21a0228-f0d5-4e72-9b29-30936ce453de','17483000-0000-4000-8000-000000000001','17484000-0000-4000-8000-000000000001','17440000-0000-4000-8000-000000000001','PS-2026-10-UTU001'),
('17485000-0000-4000-8000-000000000002','e21a0228-f0d5-4e72-9b29-30936ce453de','17483000-0000-4000-8000-000000000001','17484000-0000-4000-8000-000000000002','17440000-0000-4000-8000-000000000002','PS-2026-10-UTU002'),
('17485000-0000-4000-8000-000000000003','e21a0228-f0d5-4e72-9b29-30936ce453de','17483000-0000-4000-8000-000000000001','17484000-0000-4000-8000-000000000003','17440000-0000-4000-8000-000000000004','PS-2026-10-UTU004')
on conflict(id) do nothing;

insert into unimis.hrc_hrpay_approval_events(id,tenant_id,domain,workflow_type,reference,status,submitted_label,approved_label,notes,decided_at) values
('17490000-0000-4000-8000-000000000001','e21a0228-f0d5-4e72-9b29-30936ce453de','hr','leave','UTU008-SICK-OCT','approved','HR Officer','Owner','Approved sample leave request',now()),
('17490000-0000-4000-8000-000000000002','e21a0228-f0d5-4e72-9b29-30936ce453de','payroll','payroll_run','PR-2026-10','approved','Accountant','Owner','October payroll approved',now())
on conflict(id) do nothing;

insert into unimis.hrc_hrpay_audit_events(id,tenant_id,domain,action,entity_type,entity_reference,actor_label,new_data) values
('17491000-0000-4000-8000-000000000001','e21a0228-f0d5-4e72-9b29-30936ce453de','hr','seed_created','employee','UTU001','Build 174 seed','{"purpose":"HR integration testing"}'::jsonb),
('17491000-0000-4000-8000-000000000002','e21a0228-f0d5-4e72-9b29-30936ce453de','payroll','seed_created','payroll_run','PR-2026-10','Build 174 seed','{"purpose":"Payroll integration testing"}'::jsonb)
on conflict(id) do nothing;

select pg_notify('pgrst','reload schema');
