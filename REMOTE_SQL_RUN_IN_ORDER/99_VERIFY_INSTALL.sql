
-- UniMIS Build 172 verification. Run after all numbered install files.
NOTIFY pgrst, 'reload schema';

select
  to_regclass('unimis.hrc_tenants') is not null as tenants_ok,
  to_regclass('unimis.hrc_departments') is not null as departments_ok,
  to_regclass('unimis.hrc_branches') is not null as branches_ok,
  to_regclass('unimis.hrc_hr_employees') is not null as employees_ok,
  to_regclass('unimis.hrc_hr_positions') is not null as positions_ok,
  to_regclass('unimis.hrc_hr_job_grades') is not null as grades_ok,
  to_regclass('unimis.hrc_hr_leave_requests') is not null as leave_ok,
  to_regclass('unimis.hrc_hr_attendance_records') is not null as attendance_ok,
  to_regclass('unimis.hrc_hr_performance_cycles') is not null as performance_ok,
  to_regclass('unimis.hrc_payroll_components') is not null as payroll_components_ok,
  to_regclass('unimis.hrc_payroll_periods') is not null as payroll_periods_ok,
  to_regclass('unimis.hrc_payroll_runs') is not null as payroll_runs_ok,
  to_regclass('unimis.hrc_payroll_payslips') is not null as payslips_ok,
  to_regclass('unimis.hrc_hrpay_approval_events') is not null as approvals_ok,
  to_regclass('unimis.hrc_hrpay_audit_events') is not null as audit_ok;

select pg_notify('pgrst','reload schema');
