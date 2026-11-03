set search_path=unimis,public;
select
 (select count(*) from unimis.hrc_hr_employees where tenant_id='e21a0228-f0d5-4e72-9b29-30936ce453de') as employees,
 (select count(*) from unimis.hrc_departments where tenant_id='e21a0228-f0d5-4e72-9b29-30936ce453de') as departments,
 (select count(*) from unimis.hrc_hr_positions where tenant_id='e21a0228-f0d5-4e72-9b29-30936ce453de') as positions,
 (select count(*) from unimis.hrc_hr_attendance_records where tenant_id='e21a0228-f0d5-4e72-9b29-30936ce453de') as attendance,
 (select count(*) from unimis.hrc_hr_leave_requests where tenant_id='e21a0228-f0d5-4e72-9b29-30936ce453de') as leave_requests,
 (select count(*) from unimis.hrc_payroll_runs where tenant_id='e21a0228-f0d5-4e72-9b29-30936ce453de') as payroll_runs,
 (select count(*) from unimis.hrc_payroll_payslips where tenant_id='e21a0228-f0d5-4e72-9b29-30936ce453de') as payslips;
