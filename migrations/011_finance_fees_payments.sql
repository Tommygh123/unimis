-- ============================================================
-- UNIMIS MODULE 09
-- FINANCE, FEES, INVOICES, PAYMENTS & RECEIPTS
-- 011_finance_fees_payments.sql
-- Run AFTER Module 08
-- ============================================================

-- ============================================================
-- SECTION 09A — FEE TYPES
-- ============================================================

create table if not exists public.fee_types (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  name text not null,
  code text not null,

  description text,

  is_mandatory boolean not null default true,

  status text not null default 'active'
    check (
      status in (
        'active',
        'inactive',
        'archived'
      )
    ),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (
    institution_id,
    code
  )
);


-- ============================================================
-- SECTION 09B — FEE STRUCTURES
-- Defines applicable charges by programme/level/period.
-- ============================================================

create table if not exists public.fee_structures (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  academic_year_id uuid not null
    references public.academic_years(id)
    on delete cascade,

  academic_period_id uuid
    references public.academic_periods(id)
    on delete cascade,

  programme_id uuid
    references public.programmes(id)
    on delete set null,

  level_number integer
    check (
      level_number is null
      or level_number > 0
    ),

  student_type text
    check (
      student_type is null
      or student_type in (
        'regular',
        'mature',
        'transfer',
        'international',
        'exchange',
        'other'
      )
    ),

  name text not null,

  status text not null default 'active'
    check (
      status in (
        'draft',
        'active',
        'inactive',
        'archived'
      )
    ),

  currency_code text not null default 'GHS',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);


-- ============================================================
-- SECTION 09C — FEE STRUCTURE ITEMS
-- ============================================================

create table if not exists public.fee_structure_items (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  fee_structure_id uuid not null
    references public.fee_structures(id)
    on delete cascade,

  fee_type_id uuid not null
    references public.fee_types(id)
    on delete restrict,

  amount numeric(12,2) not null
    check (amount >= 0),

  due_date date,

  is_optional boolean not null default false,

  created_at timestamptz not null default now(),

  unique (
    fee_structure_id,
    fee_type_id
  )
);


-- ============================================================
-- SECTION 09D — STUDENT INVOICES
-- ============================================================

create table if not exists public.student_invoices (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  student_id uuid not null
    references public.students(id)
    on delete cascade,

  academic_year_id uuid
    references public.academic_years(id)
    on delete set null,

  academic_period_id uuid
    references public.academic_periods(id)
    on delete set null,

  invoice_number text not null,

  invoice_date date not null default current_date,

  due_date date,

  currency_code text not null default 'GHS',

  subtotal numeric(12,2) not null default 0
    check (subtotal >= 0),

  discount_amount numeric(12,2) not null default 0
    check (discount_amount >= 0),

  total_amount numeric(12,2) not null default 0
    check (total_amount >= 0),

  amount_paid numeric(12,2) not null default 0
    check (amount_paid >= 0),

  balance numeric(12,2) not null default 0,

  status text not null default 'unpaid'
    check (
      status in (
        'draft',
        'unpaid',
        'part_paid',
        'paid',
        'overdue',
        'cancelled',
        'waived'
      )
    ),

  notes text,

  created_by uuid
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (
    institution_id,
    invoice_number
  )
);


-- ============================================================
-- SECTION 09E — INVOICE ITEMS
-- ============================================================

create table if not exists public.student_invoice_items (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  invoice_id uuid not null
    references public.student_invoices(id)
    on delete cascade,

  fee_type_id uuid
    references public.fee_types(id)
    on delete set null,

  description text not null,

  quantity numeric(10,2) not null default 1
    check (quantity > 0),

  unit_amount numeric(12,2) not null default 0
    check (unit_amount >= 0),

  line_total numeric(12,2) not null default 0
    check (line_total >= 0),

  created_at timestamptz not null default now()
);


-- ============================================================
-- SECTION 09F — PAYMENTS
-- ============================================================

create table if not exists public.student_payments (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  student_id uuid not null
    references public.students(id)
    on delete cascade,

  invoice_id uuid
    references public.student_invoices(id)
    on delete set null,

  payment_reference text not null,

  payment_date timestamptz not null default now(),

  amount numeric(12,2) not null
    check (amount > 0),

  currency_code text not null default 'GHS',

  payment_method text not null
    check (
      payment_method in (
        'cash',
        'mobile_money',
        'bank_transfer',
        'card',
        'cheque',
        'online',
        'scholarship',
        'waiver',
        'other'
      )
    ),

  provider text,
  provider_reference text,

  status text not null default 'completed'
    check (
      status in (
        'pending',
        'completed',
        'failed',
        'reversed',
        'refunded'
      )
    ),

  received_by uuid
    references auth.users(id)
    on delete set null,

  notes text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (
    institution_id,
    payment_reference
  )
);


-- ============================================================
-- SECTION 09G — RECEIPTS
-- ============================================================

create table if not exists public.payment_receipts (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  payment_id uuid not null
    references public.student_payments(id)
    on delete cascade,

  receipt_number text not null,

  issued_at timestamptz not null default now(),

  issued_by uuid
    references auth.users(id)
    on delete set null,

  receipt_path text,

  created_at timestamptz not null default now(),

  unique (
    institution_id,
    receipt_number
  ),

  unique (
    payment_id
  )
);


-- ============================================================
-- SECTION 09H — SCHOLARSHIPS / WAIVERS
-- ============================================================

create table if not exists public.student_financial_aid (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  student_id uuid not null
    references public.students(id)
    on delete cascade,

  academic_year_id uuid
    references public.academic_years(id)
    on delete set null,

  aid_type text not null
    check (
      aid_type in (
        'scholarship',
        'bursary',
        'waiver',
        'sponsorship',
        'discount',
        'other'
      )
    ),

  sponsor_name text,

  amount numeric(12,2)
    check (
      amount is null
      or amount >= 0
    ),

  percentage numeric(5,2)
    check (
      percentage is null
      or (
        percentage >= 0
        and percentage <= 100
      )
    ),

  status text not null default 'active'
    check (
      status in (
        'pending',
        'active',
        'expired',
        'cancelled'
      )
    ),

  start_date date,
  end_date date,

  notes text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);


-- ============================================================
-- SECTION 09I — AUTOMATIC INVOICE NUMBER
-- Example: UDU-INV-2026-001001
-- ============================================================

create sequence if not exists
public.invoice_number_seq start 1001;


create or replace function
public.generate_invoice_number()

returns trigger

language plpgsql
security definer
set search_path = ''

as $$

declare

  inst_code text;
  yr text;
  seq_no bigint;

begin

  if new.invoice_number is null
     or btrim(new.invoice_number) = '' then

    select
      coalesce(
        nullif(i.short_name,''),
        i.code
      )

    into inst_code

    from public.institutions i

    where i.id =
      new.institution_id;


    if inst_code is null then

      raise exception
      'Invalid institution';

    end if;


    yr :=
      to_char(
        current_date,
        'YYYY'
      );


    seq_no :=
      nextval(
        'public.invoice_number_seq'
      );


    new.invoice_number :=

      upper(
        regexp_replace(
          inst_code,
          '[^A-Za-z0-9]',
          '',
          'g'
        )
      )

      || '-INV-'
      || yr
      || '-'
      || lpad(
           seq_no::text,
           6,
           '0'
         );

  end if;


  return new;

end;

$$;


revoke all
on function public.generate_invoice_number()
from public;


drop trigger if exists
trg_generate_invoice_number
on public.student_invoices;


create trigger
trg_generate_invoice_number

before insert
on public.student_invoices

for each row

execute function
public.generate_invoice_number();


-- ============================================================
-- SECTION 09J — AUTOMATIC PAYMENT REFERENCE
-- ============================================================

create sequence if not exists
public.payment_reference_seq start 1001;


create or replace function
public.generate_payment_reference()

returns trigger

language plpgsql
security definer
set search_path = ''

as $$

declare

  inst_code text;
  yr text;
  seq_no bigint;

begin

  if new.payment_reference is null
     or btrim(new.payment_reference) = '' then

    select
      coalesce(
        nullif(i.short_name,''),
        i.code
      )

    into inst_code

    from public.institutions i

    where i.id =
      new.institution_id;


    if inst_code is null then

      raise exception
      'Invalid institution';

    end if;


    yr :=
      to_char(
        current_date,
        'YYYY'
      );


    seq_no :=
      nextval(
        'public.payment_reference_seq'
      );


    new.payment_reference :=

      upper(
        regexp_replace(
          inst_code,
          '[^A-Za-z0-9]',
          '',
          'g'
        )
      )

      || '-PAY-'
      || yr
      || '-'
      || lpad(
           seq_no::text,
           6,
           '0'
         );

  end if;


  return new;

end;

$$;


revoke all
on function public.generate_payment_reference()
from public;


drop trigger if exists
trg_generate_payment_reference
on public.student_payments;


create trigger
trg_generate_payment_reference

before insert
on public.student_payments

for each row

execute function
public.generate_payment_reference();


-- ============================================================
-- SECTION 09K — AUTOMATIC RECEIPT NUMBER
-- ============================================================

create sequence if not exists
public.receipt_number_seq start 1001;


create or replace function
public.generate_receipt_number()

returns trigger

language plpgsql
security definer
set search_path = ''

as $$

declare

  inst_code text;
  yr text;
  seq_no bigint;

begin

  if new.receipt_number is null
     or btrim(new.receipt_number) = '' then

    select
      coalesce(
        nullif(i.short_name,''),
        i.code
      )

    into inst_code

    from public.institutions i

    where i.id =
      new.institution_id;


    if inst_code is null then

      raise exception
      'Invalid institution';

    end if;


    yr :=
      to_char(
        current_date,
        'YYYY'
      );


    seq_no :=
      nextval(
        'public.receipt_number_seq'
      );


    new.receipt_number :=

      upper(
        regexp_replace(
          inst_code,
          '[^A-Za-z0-9]',
          '',
          'g'
        )
      )

      || '-RCT-'
      || yr
      || '-'
      || lpad(
           seq_no::text,
           6,
           '0'
         );

  end if;


  return new;

end;

$$;


revoke all
on function public.generate_receipt_number()
from public;


drop trigger if exists
trg_generate_receipt_number
on public.payment_receipts;


create trigger
trg_generate_receipt_number

before insert
on public.payment_receipts

for each row

execute function
public.generate_receipt_number();


-- ============================================================
-- SECTION 09L — INVOICE ITEM TOTAL
-- ============================================================

create or replace function
public.calculate_invoice_item_total()

returns trigger

language plpgsql

as $$

begin

  new.line_total :=
    round(
      new.quantity
      *
      new.unit_amount,
      2
    );


  return new;

end;

$$;


drop trigger if exists
trg_calculate_invoice_item_total
on public.student_invoice_items;


create trigger
trg_calculate_invoice_item_total

before insert
or update of quantity, unit_amount

on public.student_invoice_items

for each row

execute function
public.calculate_invoice_item_total();


-- ============================================================
-- SECTION 09M — RECALCULATE INVOICE TOTALS
-- ============================================================

create or replace function
public.recalculate_invoice_totals(
  requested_invoice_id uuid
)

returns void

language plpgsql
security definer
set search_path = ''

as $$

declare

  inv_inst uuid;
  total_sub numeric(12,2);
  total_paid numeric(12,2);
  disc numeric(12,2);
  final_total numeric(12,2);
  final_balance numeric(12,2);
  final_status text;

begin

  select
    institution_id,
    discount_amount

  into
    inv_inst,
    disc

  from public.student_invoices

  where id =
    requested_invoice_id;


  if inv_inst is null then

    raise exception
    'Invoice not found';

  end if;


  if not public.has_permission(
         inv_inst,
         'finance.manage'
       ) then

    raise exception
    'Not authorised';

  end if;


  select
    coalesce(
      sum(line_total),
      0
    )

  into total_sub

  from public.student_invoice_items

  where invoice_id =
    requested_invoice_id;


  select
    coalesce(
      sum(amount),
      0
    )

  into total_paid

  from public.student_payments

  where invoice_id =
    requested_invoice_id

    and status = 'completed';


  final_total :=
    greatest(
      total_sub
      -
      coalesce(
        disc,
        0
      ),
      0
    );


  final_balance :=
    final_total
    -
    total_paid;


  final_status :=

    case

      when final_total = 0
        then 'paid'

      when total_paid <= 0
        then 'unpaid'

      when final_balance <= 0
        then 'paid'

      else 'part_paid'

    end;


  update public.student_invoices

  set
    subtotal =
      total_sub,

    total_amount =
      final_total,

    amount_paid =
      total_paid,

    balance =
      final_balance,

    status =
      final_status,

    updated_at =
      now()

  where id =
    requested_invoice_id;

end;

$$;


revoke all
on function public.recalculate_invoice_totals(uuid)
from public;


grant execute
on function public.recalculate_invoice_totals(uuid)
to authenticated;


-- ============================================================
-- SECTION 09N — AUTOMATIC RECEIPT AFTER COMPLETED PAYMENT
-- ============================================================

create or replace function
public.create_receipt_after_payment()

returns trigger

language plpgsql
security definer
set search_path = ''

as $$

begin

  if new.status = 'completed'
     and (
       tg_op = 'INSERT'
       or old.status is distinct from new.status
     ) then

    insert into public.payment_receipts (
      institution_id,
      payment_id,
      receipt_number,
      issued_by
    )

    values (
      new.institution_id,
      new.id,
      '',
      new.received_by
    )

    on conflict (
      payment_id
    )

    do nothing;

  end if;


  return new;

end;

$$;


revoke all
on function public.create_receipt_after_payment()
from public;


drop trigger if exists
trg_create_receipt_after_payment
on public.student_payments;


create trigger
trg_create_receipt_after_payment

after insert
or update of status

on public.student_payments

for each row

execute function
public.create_receipt_after_payment();


-- ============================================================
-- SECTION 09O — FINANCE PERMISSIONS
-- ============================================================

insert into public.permissions (
  code,
  name,
  module,
  description
)

values

  (
    'fees.manage',
    'Manage Fee Structures',
    'finance',
    'Create and manage fee structures'
  ),

  (
    'invoices.manage',
    'Manage Student Invoices',
    'finance',
    'Create and manage student invoices'
  ),

  (
    'payments.receive',
    'Receive Payments',
    'finance',
    'Record student payments'
  ),

  (
    'receipts.view',
    'View Receipts',
    'finance',
    'View and print payment receipts'
  )

on conflict (code)

do update set

  name =
    excluded.name,

  module =
    excluded.module,

  description =
    excluded.description;


-- Owner/Admin
insert into public.role_permissions (
  role_id,
  permission_id
)

select
  r.id,
  p.id

from public.roles r

join public.institutions i
  on i.id =
     r.institution_id

join public.permissions p
  on p.code in (
    'fees.manage',
    'invoices.manage',
    'payments.receive',
    'receipts.view'
  )

where
  i.code =
    'UNIMIS-DEMO-UNIV'

  and r.code in (
    'owner',
    'admin'
  )

on conflict do nothing;


-- Finance Officer
insert into public.role_permissions (
  role_id,
  permission_id
)

select
  r.id,
  p.id

from public.roles r

join public.institutions i
  on i.id =
     r.institution_id

join public.permissions p
  on p.code in (
    'fees.manage',
    'invoices.manage',
    'payments.receive',
    'receipts.view'
  )

where
  i.code =
    'UNIMIS-DEMO-UNIV'

  and r.code =
    'finance_officer'

on conflict do nothing;


-- Student
insert into public.role_permissions (
  role_id,
  permission_id
)

select
  r.id,
  p.id

from public.roles r

join public.institutions i
  on i.id =
     r.institution_id

join public.permissions p
  on p.code =
     'receipts.view'

where
  i.code =
    'UNIMIS-DEMO-UNIV'

  and r.code =
    'student'

on conflict do nothing;


-- ============================================================
-- SECTION 09P — INDEXES
-- ============================================================

create index if not exists idx_fee_types_institution
on public.fee_types(institution_id);

create index if not exists idx_fee_structures_institution
on public.fee_structures(institution_id);

create index if not exists idx_fee_structures_year
on public.fee_structures(academic_year_id);

create index if not exists idx_fee_structure_items_structure
on public.fee_structure_items(fee_structure_id);

create index if not exists idx_student_invoices_student
on public.student_invoices(student_id);

create index if not exists idx_student_invoices_status
on public.student_invoices(institution_id, status);

create index if not exists idx_invoice_items_invoice
on public.student_invoice_items(invoice_id);

create index if not exists idx_student_payments_student
on public.student_payments(student_id);

create index if not exists idx_student_payments_invoice
on public.student_payments(invoice_id);

create index if not exists idx_receipts_payment
on public.payment_receipts(payment_id);

create index if not exists idx_financial_aid_student
on public.student_financial_aid(student_id);


-- ============================================================
-- SECTION 09Q — UPDATED_AT TRIGGERS
-- ============================================================

do $$

declare
  t text;

begin

  foreach t in array array[
    'fee_types',
    'fee_structures',
    'student_invoices',
    'student_payments',
    'student_financial_aid'
  ]

  loop

    execute format(
      'drop trigger if exists trg_%I_updated_at
       on public.%I',
      t,
      t
    );

    execute format(
      'create trigger trg_%I_updated_at
       before update on public.%I
       for each row
       execute function public.set_updated_at()',
      t,
      t
    );

  end loop;

end $$;


-- ============================================================
-- SECTION 09R — ENABLE RLS
-- ============================================================

alter table public.fee_types
enable row level security;

alter table public.fee_structures
enable row level security;

alter table public.fee_structure_items
enable row level security;

alter table public.student_invoices
enable row level security;

alter table public.student_invoice_items
enable row level security;

alter table public.student_payments
enable row level security;

alter table public.payment_receipts
enable row level security;

alter table public.student_financial_aid
enable row level security;


-- ============================================================
-- SECTION 09S — FINANCE STAFF RLS
-- ============================================================

do $$

declare
  t text;

begin

  foreach t in array array[
    'fee_types',
    'fee_structures',
    'fee_structure_items',
    'student_invoices',
    'student_invoice_items',
    'student_payments',
    'payment_receipts',
    'student_financial_aid'
  ]

  loop

    execute format(
      'drop policy if exists
       "Finance viewers can view %s"
       on public.%I',
      t,
      t
    );

    execute format(
      'create policy
       "Finance viewers can view %s"
       on public.%I
       for select
       to authenticated
       using (
         public.has_permission(
           institution_id,
           ''finance.view''
         )
         or public.has_permission(
           institution_id,
           ''finance.manage''
         )
         or public.has_permission(
           institution_id,
           ''fees.manage''
         )
         or public.has_permission(
           institution_id,
           ''invoices.manage''
         )
         or public.has_permission(
           institution_id,
           ''payments.receive''
         )
         or public.has_permission(
           institution_id,
           ''receipts.view''
         )
       )',
      t,
      t
    );

    execute format(
      'drop policy if exists
       "Finance managers can manage %s"
       on public.%I',
      t,
      t
    );

    execute format(
      'create policy
       "Finance managers can manage %s"
       on public.%I
       for all
       to authenticated
       using (
         public.has_permission(
           institution_id,
           ''finance.manage''
         )
         or public.has_permission(
           institution_id,
           ''fees.manage''
         )
         or public.has_permission(
           institution_id,
           ''invoices.manage''
         )
         or public.has_permission(
           institution_id,
           ''payments.receive''
         )
       )
       with check (
         public.has_permission(
           institution_id,
           ''finance.manage''
         )
         or public.has_permission(
           institution_id,
           ''fees.manage''
         )
         or public.has_permission(
           institution_id,
           ''invoices.manage''
         )
         or public.has_permission(
           institution_id,
           ''payments.receive''
         )
       )',
      t,
      t
    );

  end loop;

end $$;


-- ============================================================
-- SECTION 09T — STUDENT SELF-SERVICE FINANCE ACCESS
-- ============================================================

drop policy if exists
"Students can view own invoices"
on public.student_invoices;


create policy
"Students can view own invoices"

on public.student_invoices

for select

to authenticated

using (
  exists (
    select 1

    from public.students s

    where s.id =
      student_id

      and s.user_id =
          (select auth.uid())
  )
);


drop policy if exists
"Students can view own invoice items"
on public.student_invoice_items;


create policy
"Students can view own invoice items"

on public.student_invoice_items

for select

to authenticated

using (
  exists (
    select 1

    from public.student_invoices si

    join public.students s
      on s.id =
         si.student_id

    where si.id =
      invoice_id

      and s.user_id =
          (select auth.uid())
  )
);


drop policy if exists
"Students can view own payments"
on public.student_payments;


create policy
"Students can view own payments"

on public.student_payments

for select

to authenticated

using (
  exists (
    select 1

    from public.students s

    where s.id =
      student_id

      and s.user_id =
          (select auth.uid())
  )
);


drop policy if exists
"Students can view own receipts"
on public.payment_receipts;


create policy
"Students can view own receipts"

on public.payment_receipts

for select

to authenticated

using (
  exists (
    select 1

    from public.student_payments sp

    join public.students s
      on s.id =
         sp.student_id

    where sp.id =
      payment_id

      and s.user_id =
          (select auth.uid())
  )
);


drop policy if exists
"Students can view own financial aid"
on public.student_financial_aid;


create policy
"Students can view own financial aid"

on public.student_financial_aid

for select

to authenticated

using (
  exists (
    select 1

    from public.students s

    where s.id =
      student_id

      and s.user_id =
          (select auth.uid())
  )
);


-- ============================================================
-- SECTION 09U — FINANCE SUMMARY VIEW
-- ============================================================

create or replace view
public.v_student_finance_summary

with (
  security_invoker = true
)

as

select

  si.id
    as invoice_id,

  si.institution_id,

  si.student_id,

  s.student_number,

  concat_ws(
    ' ',
    s.first_name,
    s.middle_name,
    s.last_name
  )
    as student_name,

  si.invoice_number,

  si.invoice_date,

  si.due_date,

  si.currency_code,

  si.total_amount,

  si.amount_paid,

  si.balance,

  si.status

from public.student_invoices si

join public.students s
  on s.id =
     si.student_id;


-- ============================================================
-- SECTION 09V — VERIFY MODULE 09
-- ============================================================

select

  (
    select count(*)
    from public.fee_types
  )
  as fee_types,

  (
    select count(*)
    from public.fee_structures
  )
  as fee_structures,

  (
    select count(*)
    from public.student_invoices
  )
  as invoices,

  (
    select count(*)
    from public.student_payments
  )
  as payments,

  (
    select count(*)
    from public.payment_receipts
  )
  as receipts;


-- ============================================================
-- END UNIMIS MODULE 09
-- FINANCE, FEES, INVOICES, PAYMENTS & RECEIPTS
-- ============================================================
