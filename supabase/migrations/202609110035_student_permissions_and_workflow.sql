-- Student lifecycle permissions
begin;

insert into public.permissions(code,name,module,description)
values
 ('students.view','View Students','students','View student records and enrolments'),
 ('students.manage','Manage Students','students','Convert applicants, edit student records and enrolments'),
 ('student_finance.generate','Generate Student Invoices','finance','Generate student invoices from configured fee structures')
on conflict(code) do update
set name=excluded.name,module=excluded.module,description=excluded.description;

-- Administrator gets full student management.
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id
from public.roles r
cross join public.permissions p
where r.code in ('admin','owner')
  and p.code in ('students.view','students.manage','student_finance.generate')
  and not exists(
    select 1 from public.role_permissions rp
    where rp.role_id=r.id and rp.permission_id=p.id
  );

-- Registrar can manage student records.
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id
from public.roles r
cross join public.permissions p
where r.code='registrar'
  and p.code in ('students.view','students.manage')
  and not exists(
    select 1 from public.role_permissions rp
    where rp.role_id=r.id and rp.permission_id=p.id
  );

-- Admissions can see conversion status, but conversion remains allowed through RPC.
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id
from public.roles r
cross join public.permissions p
where r.code='admissions_officer'
  and p.code='students.view'
  and not exists(
    select 1 from public.role_permissions rp
    where rp.role_id=r.id and rp.permission_id=p.id
  );

-- Finance can view students and generate invoices.
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id
from public.roles r
cross join public.permissions p
where r.code='finance_officer'
  and p.code in ('students.view','student_finance.generate')
  and not exists(
    select 1 from public.role_permissions rp
    where rp.role_id=r.id and rp.permission_id=p.id
  );

commit;
