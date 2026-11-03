-- HRPayrollCore 009h6
-- Exact compatibility fix for payroll_reverse_salary_batch().
-- The reversal RPC writes change_type = 'salary_adjustment_reversal'.

alter table public.hr_salary_history
  drop constraint if exists hr_salary_history_change_type_check;

alter table public.hr_salary_history
  add constraint hr_salary_history_change_type_check
  check (
    change_type = any (
      array[
        'initial'::text,
        'manual'::text,
        'grade_step'::text,
        'promotion'::text,
        'bulk_adjustment'::text,
        'correction'::text,
        'reversal'::text,
        'salary_adjustment_reversal'::text
      ]
    )
  );

notify pgrst, 'reload schema';
