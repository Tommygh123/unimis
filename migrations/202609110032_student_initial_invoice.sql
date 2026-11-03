-- Initial student invoice generation from fee structure
begin;

create table if not exists public.student_invoice_sequences (
  institution_id uuid not null,
  academic_year integer not null,
  last_number bigint not null default 0,
  updated_at timestamptz not null default now(),
  primary key(institution_id,academic_year)
);

create or replace function public.unimis_generate_student_initial_invoice(
  p_student_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_student public.students%rowtype;
  v_enrol public.student_programme_enrolments%rowtype;
  v_year public.academic_years%rowtype;
  v_period public.academic_periods%rowtype;
  v_structure public.fee_structures%rowtype;
  v_invoice public.student_invoices%rowtype;
  v_seq bigint;
  v_total numeric:=0;
begin
  select * into v_student from public.students where id=p_student_id;
  if not found then raise exception 'Student not found'; end if;

  if not (
    public.has_permission(v_student.institution_id,'finance.manage')
    or public.has_permission(v_student.institution_id,'students.manage')
  ) then
    raise exception 'You do not have permission to generate student invoices';
  end if;

  select * into v_enrol
  from public.student_programme_enrolments
  where student_id=p_student_id and is_primary=true
  order by created_at desc limit 1;

  select * into v_year
  from public.academic_years
  where institution_id=v_student.institution_id and is_current=true
  order by start_date desc limit 1;

  if not found then raise exception 'No current academic year configured'; end if;

  select * into v_period
  from public.academic_periods
  where institution_id=v_student.institution_id
    and academic_year_id=v_year.id and is_current=true
  order by period_number limit 1;

  if exists(
    select 1 from public.student_invoices
    where student_id=p_student_id
      and academic_year_id=v_year.id
      and (academic_period_id is not distinct from v_period.id)
  ) then
    select * into v_invoice
    from public.student_invoices
    where student_id=p_student_id
      and academic_year_id=v_year.id
      and (academic_period_id is not distinct from v_period.id)
    order by created_at desc limit 1;
    return jsonb_build_object('ok',true,'already_exists',true,'invoice_id',v_invoice.id,'invoice_number',v_invoice.invoice_number);
  end if;

  select * into v_structure
  from public.fee_structures fs
  where fs.institution_id=v_student.institution_id
    and fs.academic_year_id=v_year.id
    and fs.status='active'
    and (fs.academic_period_id is null or fs.academic_period_id=v_period.id)
    and (fs.programme_id is null or fs.programme_id=v_enrol.programme_id)
    and (fs.level_number is null or fs.level_number=v_enrol.current_level)
    and (fs.student_type is null or fs.student_type=v_student.student_type)
  order by
    (fs.programme_id is not null)::int desc,
    (fs.level_number is not null)::int desc,
    (fs.academic_period_id is not null)::int desc
  limit 1;

  if not found then
    return jsonb_build_object('ok',false,'reason','no_fee_structure','message','No matching active fee structure is configured.');
  end if;

  insert into public.student_invoice_sequences(institution_id,academic_year,last_number)
  values(v_student.institution_id,extract(year from v_year.start_date)::integer,1)
  on conflict(institution_id,academic_year)
  do update set last_number=public.student_invoice_sequences.last_number+1,updated_at=now()
  returning last_number into v_seq;

  select coalesce(sum(amount),0) into v_total
  from public.fee_structure_items where fee_structure_id=v_structure.id;

  insert into public.student_invoices(
    institution_id,student_id,academic_year_id,academic_period_id,
    invoice_number,invoice_date,currency_code,subtotal,total_amount,
    amount_paid,balance,status,notes,created_by
  ) values (
    v_student.institution_id,v_student.id,v_year.id,v_period.id,
    'INV/'||extract(year from v_year.start_date)::integer||'/'||lpad(v_seq::text,6,'0'),
    current_date,v_structure.currency_code,v_total,v_total,0,v_total,
    case when v_total=0 then 'paid' else 'unpaid' end,
    'Initial invoice generated from fee structure: '||v_structure.name,
    auth.uid()
  ) returning * into v_invoice;

  insert into public.student_invoice_items(
    institution_id,invoice_id,fee_type_id,description,quantity,unit_amount,line_total
  )
  select
    v_student.institution_id,v_invoice.id,fsi.fee_type_id,
    coalesce(ft.name,'Student fee'),1,fsi.amount,fsi.amount
  from public.fee_structure_items fsi
  left join public.fee_types ft on ft.id=fsi.fee_type_id
  where fsi.fee_structure_id=v_structure.id;

  return jsonb_build_object(
    'ok',true,'invoice_id',v_invoice.id,'invoice_number',v_invoice.invoice_number,
    'total_amount',v_invoice.total_amount,'currency',v_invoice.currency_code
  );
end $$;

grant execute on function public.unimis_generate_student_initial_invoice(uuid) to authenticated;

commit;
