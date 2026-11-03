-- ============================================================
-- UNIMIS MODULE 11
-- LIBRARY MANAGEMENT
-- 013_library_management.sql
-- Run AFTER Module 10
-- ============================================================

-- ============================================================
-- SECTION 11A — LIBRARY CATEGORIES
-- ============================================================

create table if not exists public.library_categories (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  name text not null,
  code text not null,
  description text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (institution_id, code)
);


-- ============================================================
-- SECTION 11B — LIBRARY ITEMS / TITLES
-- Books, journals, theses, manuals, digital resources, etc.
-- ============================================================

create table if not exists public.library_items (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  category_id uuid
    references public.library_categories(id)
    on delete set null,

  title text not null,
  subtitle text,

  author text,
  publisher text,
  publication_year integer,

  isbn text,
  issn text,

  edition text,

  item_type text not null default 'book'
    check (
      item_type in (
        'book',
        'journal',
        'thesis',
        'project',
        'manual',
        'magazine',
        'newspaper',
        'digital_resource',
        'other'
      )
    ),

  language text default 'English',

  description text,

  digital_url text,

  status text not null default 'active'
    check (
      status in (
        'active',
        'inactive',
        'archived'
      )
    ),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);


-- ============================================================
-- SECTION 11C — PHYSICAL COPIES
-- ============================================================

create table if not exists public.library_copies (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  library_item_id uuid not null
    references public.library_items(id)
    on delete cascade,

  accession_number text not null,

  barcode text,

  shelf_location text,

  acquisition_date date,

  acquisition_cost numeric(12,2)
    check (
      acquisition_cost is null
      or acquisition_cost >= 0
    ),

  condition_status text not null default 'good'
    check (
      condition_status in (
        'new',
        'good',
        'fair',
        'poor',
        'damaged',
        'lost'
      )
    ),

  availability_status text not null default 'available'
    check (
      availability_status in (
        'available',
        'borrowed',
        'reserved',
        'lost',
        'damaged',
        'repair',
        'withdrawn'
      )
    ),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (
    institution_id,
    accession_number
  ),

  unique (
    institution_id,
    barcode
  )
);


-- ============================================================
-- SECTION 11D — LIBRARY MEMBERS
-- Links students/staff to borrowing accounts.
-- ============================================================

create table if not exists public.library_members (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  user_id uuid
    references auth.users(id)
    on delete set null,

  student_id uuid
    references public.students(id)
    on delete cascade,

  staff_id uuid
    references public.staff(id)
    on delete cascade,

  member_number text not null,

  member_type text not null
    check (
      member_type in (
        'student',
        'staff',
        'lecturer',
        'external',
        'other'
      )
    ),

  max_items integer not null default 3
    check (max_items > 0),

  loan_days integer not null default 14
    check (loan_days > 0),

  status text not null default 'active'
    check (
      status in (
        'active',
        'suspended',
        'expired',
        'inactive'
      )
    ),

  joined_at date not null default current_date,
  expires_at date,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (
    institution_id,
    member_number
  ),

  check (
    student_id is not null
    or staff_id is not null
    or user_id is not null
  )
);


-- ============================================================
-- SECTION 11E — LOANS / BORROWING
-- ============================================================

create table if not exists public.library_loans (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  member_id uuid not null
    references public.library_members(id)
    on delete cascade,

  copy_id uuid not null
    references public.library_copies(id)
    on delete restrict,

  borrowed_at timestamptz not null default now(),

  due_at timestamptz not null,

  returned_at timestamptz,

  loan_status text not null default 'borrowed'
    check (
      loan_status in (
        'borrowed',
        'returned',
        'overdue',
        'lost',
        'cancelled'
      )
    ),

  issued_by uuid
    references auth.users(id)
    on delete set null,

  received_by uuid
    references auth.users(id)
    on delete set null,

  remarks text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);


-- ============================================================
-- SECTION 11F — RESERVATIONS
-- ============================================================

create table if not exists public.library_reservations (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  member_id uuid not null
    references public.library_members(id)
    on delete cascade,

  library_item_id uuid not null
    references public.library_items(id)
    on delete cascade,

  reserved_at timestamptz not null default now(),

  expires_at timestamptz,

  status text not null default 'active'
    check (
      status in (
        'active',
        'fulfilled',
        'cancelled',
        'expired'
      )
    ),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);


-- ============================================================
-- SECTION 11G — FINES
-- ============================================================

create table if not exists public.library_fines (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  member_id uuid not null
    references public.library_members(id)
    on delete cascade,

  loan_id uuid
    references public.library_loans(id)
    on delete set null,

  fine_type text not null
    check (
      fine_type in (
        'overdue',
        'lost',
        'damage',
        'replacement',
        'other'
      )
    ),

  amount numeric(12,2) not null
    check (amount >= 0),

  amount_paid numeric(12,2) not null default 0
    check (amount_paid >= 0),

  status text not null default 'unpaid'
    check (
      status in (
        'unpaid',
        'part_paid',
        'paid',
        'waived',
        'cancelled'
      )
    ),

  assessed_at timestamptz not null default now(),

  paid_at timestamptz,

  notes text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);


-- ============================================================
-- SECTION 11H — LIBRARY PERMISSIONS
-- ============================================================

insert into public.permissions (
  code,
  name,
  module,
  description
)
values
  (
    'library.view',
    'View Library',
    'library',
    'View library catalogue and circulation information'
  ),
  (
    'library.manage',
    'Manage Library',
    'library',
    'Manage catalogue, copies, members and library settings'
  ),
  (
    'library.circulation',
    'Manage Circulation',
    'library',
    'Issue, return and reserve library materials'
  ),
  (
    'library.fines',
    'Manage Library Fines',
    'library',
    'Assess and manage library fines'
  )
on conflict (code)
do update set
  name = excluded.name,
  module = excluded.module,
  description = excluded.description;


-- ============================================================
-- SECTION 11I — LIBRARIAN ROLE
-- ============================================================

insert into public.roles (
  institution_id,
  name,
  code,
  description,
  is_system_role,
  is_active
)
select
  i.id,
  'Librarian',
  'librarian',
  'Library catalogue and circulation management',
  false,
  true
from public.institutions i
where i.code = 'UNIMIS-DEMO-UNIV'
on conflict (institution_id, code)
do update set
  name = excluded.name,
  description = excluded.description,
  is_active = true,
  updated_at = now();


-- ============================================================
-- SECTION 11J — ROLE PERMISSION ASSIGNMENTS
-- ============================================================

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
  on i.id = r.institution_id
join public.permissions p
  on p.code in (
    'library.view',
    'library.manage',
    'library.circulation',
    'library.fines'
  )
where i.code = 'UNIMIS-DEMO-UNIV'
  and r.code in ('owner','admin')
on conflict do nothing;


-- Librarian
insert into public.role_permissions (
  role_id,
  permission_id
)
select
  r.id,
  p.id
from public.roles r
join public.institutions i
  on i.id = r.institution_id
join public.permissions p
  on p.code in (
    'library.view',
    'library.manage',
    'library.circulation',
    'library.fines'
  )
where i.code = 'UNIMIS-DEMO-UNIV'
  and r.code = 'librarian'
on conflict do nothing;


-- Student/Lecturer read access
insert into public.role_permissions (
  role_id,
  permission_id
)
select
  r.id,
  p.id
from public.roles r
join public.institutions i
  on i.id = r.institution_id
join public.permissions p
  on p.code = 'library.view'
where i.code = 'UNIMIS-DEMO-UNIV'
  and r.code in ('student','lecturer')
on conflict do nothing;


-- ============================================================
-- SECTION 11K — INDEXES
-- ============================================================

create index if not exists idx_library_categories_institution
on public.library_categories(institution_id);

create index if not exists idx_library_items_institution
on public.library_items(institution_id);

create index if not exists idx_library_items_title
on public.library_items(title);

create index if not exists idx_library_items_isbn
on public.library_items(isbn);

create index if not exists idx_library_copies_item
on public.library_copies(library_item_id);

create index if not exists idx_library_copies_status
on public.library_copies(institution_id, availability_status);

create index if not exists idx_library_members_institution
on public.library_members(institution_id);

create index if not exists idx_library_members_student
on public.library_members(student_id);

create index if not exists idx_library_members_staff
on public.library_members(staff_id);

create index if not exists idx_library_loans_member
on public.library_loans(member_id);

create index if not exists idx_library_loans_copy
on public.library_loans(copy_id);

create index if not exists idx_library_loans_status
on public.library_loans(institution_id, loan_status);

create index if not exists idx_library_reservations_member
on public.library_reservations(member_id);

create index if not exists idx_library_fines_member
on public.library_fines(member_id);


-- ============================================================
-- SECTION 11L — UPDATED_AT TRIGGERS
-- ============================================================

do $$
declare
  t text;
begin

  foreach t in array array[
    'library_categories',
    'library_items',
    'library_copies',
    'library_members',
    'library_loans',
    'library_reservations',
    'library_fines'
  ]

  loop

    execute format(
      'drop trigger if exists trg_%I_updated_at on public.%I',
      t, t
    );

    execute format(
      'create trigger trg_%I_updated_at
       before update on public.%I
       for each row
       execute function public.set_updated_at()',
      t, t
    );

  end loop;

end $$;


-- ============================================================
-- SECTION 11M — ENABLE RLS
-- ============================================================

alter table public.library_categories
enable row level security;

alter table public.library_items
enable row level security;

alter table public.library_copies
enable row level security;

alter table public.library_members
enable row level security;

alter table public.library_loans
enable row level security;

alter table public.library_reservations
enable row level security;

alter table public.library_fines
enable row level security;


-- ============================================================
-- SECTION 11N — LIBRARY STAFF RLS
-- ============================================================

do $$
declare
  t text;
begin

  foreach t in array array[
    'library_categories',
    'library_items',
    'library_copies',
    'library_members',
    'library_loans',
    'library_reservations',
    'library_fines'
  ]

  loop

    execute format(
      'drop policy if exists
       "Library viewers can view %s"
       on public.%I',
      t, t
    );

    execute format(
      'create policy
       "Library viewers can view %s"
       on public.%I
       for select
       to authenticated
       using (
         public.has_permission(
           institution_id,
           ''library.view''
         )
         or public.has_permission(
           institution_id,
           ''library.manage''
         )
         or public.has_permission(
           institution_id,
           ''library.circulation''
         )
         or public.has_permission(
           institution_id,
           ''library.fines''
         )
       )',
      t, t
    );

    execute format(
      'drop policy if exists
       "Library managers can manage %s"
       on public.%I',
      t, t
    );

    execute format(
      'create policy
       "Library managers can manage %s"
       on public.%I
       for all
       to authenticated
       using (
         public.has_permission(
           institution_id,
           ''library.manage''
         )
         or public.has_permission(
           institution_id,
           ''library.circulation''
         )
         or public.has_permission(
           institution_id,
           ''library.fines''
         )
       )
       with check (
         public.has_permission(
           institution_id,
           ''library.manage''
         )
         or public.has_permission(
           institution_id,
           ''library.circulation''
         )
         or public.has_permission(
           institution_id,
           ''library.fines''
         )
       )',
      t, t
    );

  end loop;

end $$;


-- ============================================================
-- SECTION 11O — SELF-SERVICE LIBRARY ACCESS
-- ============================================================

drop policy if exists
"Members can view own library membership"
on public.library_members;

create policy
"Members can view own library membership"
on public.library_members
for select
to authenticated
using (
  user_id = (select auth.uid())
);


drop policy if exists
"Members can view own loans"
on public.library_loans;

create policy
"Members can view own loans"
on public.library_loans
for select
to authenticated
using (
  exists (
    select 1
    from public.library_members lm
    where lm.id = member_id
      and lm.user_id = (select auth.uid())
  )
);


drop policy if exists
"Members can view own reservations"
on public.library_reservations;

create policy
"Members can view own reservations"
on public.library_reservations
for select
to authenticated
using (
  exists (
    select 1
    from public.library_members lm
    where lm.id = member_id
      and lm.user_id = (select auth.uid())
  )
);


drop policy if exists
"Members can view own fines"
on public.library_fines;

create policy
"Members can view own fines"
on public.library_fines
for select
to authenticated
using (
  exists (
    select 1
    from public.library_members lm
    where lm.id = member_id
      and lm.user_id = (select auth.uid())
  )
);


-- ============================================================
-- SECTION 11P — BORROW BOOK FUNCTION
-- ============================================================

create or replace function public.borrow_library_copy(
  requested_member_id uuid,
  requested_copy_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  member_row public.library_members%rowtype;
  copy_row public.library_copies%rowtype;
  active_loans integer;
  loan_id uuid;
begin

  select *
  into member_row
  from public.library_members
  where id = requested_member_id;

  if not found then
    raise exception 'Library member not found';
  end if;

  if not public.has_permission(
    member_row.institution_id,
    'library.circulation'
  ) then
    raise exception 'Not authorised';
  end if;

  if member_row.status <> 'active' then
    raise exception 'Library member is not active';
  end if;

  select *
  into copy_row
  from public.library_copies
  where id = requested_copy_id
    and institution_id = member_row.institution_id;

  if not found then
    raise exception 'Library copy not found';
  end if;

  if copy_row.availability_status <> 'available' then
    raise exception 'Library copy is not available';
  end if;

  select count(*)
  into active_loans
  from public.library_loans
  where member_id = requested_member_id
    and loan_status in ('borrowed','overdue');

  if active_loans >= member_row.max_items then
    raise exception 'Member has reached borrowing limit';
  end if;

  insert into public.library_loans (
    institution_id,
    member_id,
    copy_id,
    borrowed_at,
    due_at,
    loan_status,
    issued_by
  )
  values (
    member_row.institution_id,
    member_row.id,
    copy_row.id,
    now(),
    now() + make_interval(days => member_row.loan_days),
    'borrowed',
    auth.uid()
  )
  returning id into loan_id;

  update public.library_copies
  set
    availability_status = 'borrowed',
    updated_at = now()
  where id = copy_row.id;

  return loan_id;

end;
$$;

revoke all
on function public.borrow_library_copy(uuid, uuid)
from public;

grant execute
on function public.borrow_library_copy(uuid, uuid)
to authenticated;


-- ============================================================
-- SECTION 11Q — RETURN BOOK FUNCTION
-- ============================================================

create or replace function public.return_library_copy(
  requested_loan_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  loan_row public.library_loans%rowtype;
begin

  select *
  into loan_row
  from public.library_loans
  where id = requested_loan_id;

  if not found then
    raise exception 'Loan not found';
  end if;

  if not public.has_permission(
    loan_row.institution_id,
    'library.circulation'
  ) then
    raise exception 'Not authorised';
  end if;

  update public.library_loans
  set
    returned_at = now(),
    loan_status = 'returned',
    received_by = auth.uid(),
    updated_at = now()
  where id = requested_loan_id;

  update public.library_copies
  set
    availability_status = 'available',
    updated_at = now()
  where id = loan_row.copy_id;

end;
$$;

revoke all
on function public.return_library_copy(uuid)
from public;

grant execute
on function public.return_library_copy(uuid)
to authenticated;


-- ============================================================
-- SECTION 11R — LIBRARY CATALOGUE VIEW
-- ============================================================

create or replace view public.v_library_catalogue
with (security_invoker = true)
as
select
  li.id as library_item_id,
  li.institution_id,
  lc.name as category_name,
  li.title,
  li.author,
  li.publisher,
  li.publication_year,
  li.isbn,
  li.item_type,
  count(lcp.id) as total_copies,
  count(lcp.id) filter (
    where lcp.availability_status = 'available'
  ) as available_copies
from public.library_items li
left join public.library_categories lc
  on lc.id = li.category_id
left join public.library_copies lcp
  on lcp.library_item_id = li.id
group by
  li.id,
  li.institution_id,
  lc.name,
  li.title,
  li.author,
  li.publisher,
  li.publication_year,
  li.isbn,
  li.item_type;


-- ============================================================
-- SECTION 11S — VERIFY MODULE 11
-- ============================================================

select
  (select count(*) from public.library_items)
    as library_items,

  (select count(*) from public.library_copies)
    as copies,

  (select count(*) from public.library_members)
    as members,

  (select count(*) from public.library_loans)
    as active_loans,

  (select count(*) from public.library_fines)
    as fines;


-- ============================================================
-- END UNIMIS MODULE 11
-- LIBRARY MANAGEMENT
-- ============================================================
