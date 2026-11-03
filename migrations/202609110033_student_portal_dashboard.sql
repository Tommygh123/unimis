-- Student portal dashboard + own-record RLS
begin;

alter table public.students enable row level security;
alter table public.student_programme_enrolments enable row level security;
alter table public.student_period_registrations enable row level security;
alter table public.student_invoices enable row level security;
alter table public.student_invoice_items enable row level security;
alter table public.student_payments enable row level security;

drop policy if exists "Students view own student record" on public.students;
create policy "Students view own student record"
on public.students for select to authenticated
using (user_id=auth.uid());

drop policy if exists "Students view own programme enrolments" on public.student_programme_enrolments;
create policy "Students view own programme enrolments"
on public.student_programme_enrolments for select to authenticated
using (exists(select 1 from public.students s where s.id=student_id and s.user_id=auth.uid()));

drop policy if exists "Students view own period registrations" on public.student_period_registrations;
create policy "Students view own period registrations"
on public.student_period_registrations for select to authenticated
using (exists(select 1 from public.students s where s.id=student_id and s.user_id=auth.uid()));

drop policy if exists "Students view own invoices" on public.student_invoices;
create policy "Students view own invoices"
on public.student_invoices for select to authenticated
using (exists(select 1 from public.students s where s.id=student_id and s.user_id=auth.uid()));

drop policy if exists "Students view own invoice items" on public.student_invoice_items;
create policy "Students view own invoice items"
on public.student_invoice_items for select to authenticated
using (
  exists(
    select 1 from public.student_invoices i
    join public.students s on s.id=i.student_id
    where i.id=invoice_id and s.user_id=auth.uid()
  )
);

drop policy if exists "Students view own payments" on public.student_payments;
create policy "Students view own payments"
on public.student_payments for select to authenticated
using (exists(select 1 from public.students s where s.id=student_id and s.user_id=auth.uid()));

create or replace function public.unimis_student_portal_dashboard()
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_student public.students%rowtype;
  v_enrol jsonb;
  v_period jsonb;
  v_finance jsonb;
begin
  select * into v_student
  from public.students
  where user_id=auth.uid()
  limit 1;

  if not found then
    raise exception 'No student record is linked to this login';
  end if;

  select to_jsonb(x) into v_enrol from (
    select e.*,p.code as programme_code,p.name as programme_name,
      ay.name as admission_academic_year
    from public.student_programme_enrolments e
    join public.programmes p on p.id=e.programme_id
    left join public.academic_years ay on ay.id=e.admission_academic_year_id
    where e.student_id=v_student.id and e.is_primary=true
    order by e.created_at desc limit 1
  ) x;

  select to_jsonb(x) into v_period from (
    select r.*,ay.name as academic_year,ap.name as academic_period
    from public.student_period_registrations r
    join public.academic_years ay on ay.id=r.academic_year_id
    join public.academic_periods ap on ap.id=r.academic_period_id
    where r.student_id=v_student.id
    order by r.created_at desc limit 1
  ) x;

  select jsonb_build_object(
    'total_invoiced',coalesce(sum(total_amount),0),
    'total_paid',coalesce(sum(amount_paid),0),
    'balance',coalesce(sum(balance),0),
    'currency',coalesce(max(currency_code),'GHS')
  ) into v_finance
  from public.student_invoices
  where student_id=v_student.id;

  return jsonb_build_object(
    'student',to_jsonb(v_student),
    'enrolment',coalesce(v_enrol,'{}'::jsonb),
    'period_registration',coalesce(v_period,'{}'::jsonb),
    'finance',coalesce(v_finance,'{}'::jsonb)
  );
end $$;

grant execute on function public.unimis_student_portal_dashboard() to authenticated;

commit;
