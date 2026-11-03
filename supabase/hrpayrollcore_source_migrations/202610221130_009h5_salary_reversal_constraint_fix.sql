-- HRPayrollCore 009h5
-- Permit audited salary-adjustment reversal history entries.
-- Preserves every previously allowed hr_salary_history.change_type value.

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
        'reversal'::text
      ]
    )
  );

notify pgrst, 'reload schema';
