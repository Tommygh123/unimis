begin;
create table if not exists public.unimis_operations_events152(id uuid primary key default gen_random_uuid(),institution_id uuid not null references public.institutions(id),actor_id uuid references auth.users(id),entity text not null,record_id uuid not null,action text not null,note text,changed_fields text[],created_at timestamptz not null default now());
create table if not exists public.unimis_jobs152(id uuid primary key default gen_random_uuid(),institution_id uuid not null references public.institutions(id),title text not null,department_id uuid references public.departments(id),positions integer not null check(positions>0),closing_date date not null,description text not null,requirements text,status text not null default 'draft' check(status in('draft','open','closed','cancelled')),created_by uuid references auth.users(id),created_at timestamptz not null default now());
create table if not exists public.unimis_candidates152(id uuid primary key default gen_random_uuid(),institution_id uuid not null references public.institutions(id),job_id uuid not null references public.unimis_jobs152(id),first_name text not null,last_name text not null,email text not null,phone text,evidence text,status text not null default 'applied' check(status in('applied','shortlisted','interviewed','offered','hired','rejected')),staff_id uuid references public.staff(id),created_by uuid references auth.users(id),created_at timestamptz not null default now(),unique(job_id,email));
create table if not exists public.unimis_sites152(id uuid primary key default gen_random_uuid(),institution_id uuid not null references public.institutions(id),name text not null,latitude double precision not null check(latitude between -90 and 90),longitude double precision not null check(longitude between -180 and 180),radius_m integer not null check(radius_m between 10 and 10000),require_gps boolean not null default true,nfc_token text not null check(length(nfc_token)>=12),start_time time not null default '08:00',grace_minutes integer not null default 15 check(grace_minutes between 0 and 120),timezone text not null default 'Africa/Accra',created_by uuid references auth.users(id),created_at timestamptz not null default now(),unique(institution_id,nfc_token));
create table if not exists public.unimis_attendance_tokens152(id uuid primary key default gen_random_uuid(),institution_id uuid not null references public.institutions(id),site_id uuid not null references public.unimis_sites152(id),token uuid not null default gen_random_uuid(),expires_at timestamptz not null,created_by uuid references auth.users(id),unique(token));
create table if not exists public.unimis_staff_attendance152(id uuid primary key default gen_random_uuid(),institution_id uuid not null references public.institutions(id),staff_id uuid not null references public.staff(id),site_id uuid references public.unimis_sites152(id),work_date date not null,check_in timestamptz not null,check_out timestamptz,method text not null check(method in('qr','nfc','exception')),latitude double precision,longitude double precision,accuracy_m double precision,late_minutes integer not null default 0,status text not null default 'recorded' check(status in('recorded','corrected')),created_at timestamptz not null default now(),unique(staff_id,work_date),check(check_out is null or check_out>check_in));
create table if not exists public.unimis_attendance_exceptions152(id uuid primary key default gen_random_uuid(),institution_id uuid not null references public.institutions(id),staff_id uuid not null references public.staff(id),work_date date not null,requested_in timestamptz not null,requested_out timestamptz,reason text not null,status text not null default 'submitted' check(status in('submitted','approved','rejected')),created_by uuid references auth.users(id),approved_by uuid references auth.users(id),approved_at timestamptz,created_at timestamptz not null default now(),check(requested_out is null or requested_out>requested_in));
create table if not exists public.unimis_performance152(id uuid primary key default gen_random_uuid(),institution_id uuid not null references public.institutions(id),staff_id uuid not null references public.staff(id),period_start date not null,period_end date not null,model text not null check(model in('kpi','competency','balanced')),kpi_score numeric not null check(kpi_score between 0 and 100),competency_score numeric not null check(competency_score between 0 and 100),kpi_weight numeric not null check(kpi_weight between 0 and 100),final_score numeric generated always as (case model when 'kpi' then kpi_score when 'competency' then competency_score else round((kpi_score*kpi_weight+competency_score*(100-kpi_weight))/100,2) end) stored,evidence text not null,goals text,development_plan text,employee_response text,status text not null default 'draft' check(status in('draft','submitted','returned','approved','acknowledged')),created_by uuid references auth.users(id),approved_by uuid references auth.users(id),approved_at timestamptz,created_at timestamptz not null default now(),check(period_end>=period_start));
create table if not exists public.unimis_objectives152(id uuid primary key default gen_random_uuid(),institution_id uuid not null references public.institutions(id),staff_id uuid not null references public.staff(id),title text not null,category text not null check(category in('kpi','competency','milestone')),start_date date not null,due_date date not null,target numeric not null check(target>0),actual numeric not null default 0 check(actual>=0),unit text not null,evidence text,progress numeric generated always as(least(100,round(actual/target*100,1))) stored,status text not null default 'open' check(status in('open','completed','accepted','returned')),created_by uuid references auth.users(id),approved_by uuid references auth.users(id),approved_at timestamptz,created_at timestamptz not null default now(),check(due_date>=start_date));
create table if not exists public.unimis_requisition_items152(id uuid primary key default gen_random_uuid(),institution_id uuid not null references public.institutions(id),requisition_id uuid not null references public.purchase_requisitions(id),description text not null,quantity numeric not null check(quantity>0),unit_cost numeric not null check(unit_cost>=0),line_total numeric generated always as (round(quantity*unit_cost,2)) stored,created_at timestamptz not null default now());
create table if not exists public.unimis_order_items152(id uuid primary key default gen_random_uuid(),institution_id uuid not null references public.institutions(id),order_id uuid not null references public.purchase_orders(id),description text not null,quantity numeric not null check(quantity>0),unit_cost numeric not null check(unit_cost>=0),line_total numeric generated always as(round(quantity*unit_cost,2)) stored,created_at timestamptz not null default now());
create table if not exists public.unimis_goods_receipts152(id uuid primary key default gen_random_uuid(),institution_id uuid not null references public.institutions(id),order_id uuid not null references public.purchase_orders(id),order_item_id uuid not null references public.unimis_order_items152(id),quantity numeric not null check(quantity>0),delivery_reference text not null,inspection_notes text not null,status text not null default 'draft' check(status in('draft','accepted','rejected')),created_by uuid references auth.users(id),approved_by uuid references auth.users(id),approved_at timestamptz,created_at timestamptz not null default now());
create table if not exists public.unimis_supplier_invoices152(id uuid primary key default gen_random_uuid(),institution_id uuid not null references public.institutions(id),order_id uuid not null references public.purchase_orders(id),invoice_number text not null,invoice_date date not null,amount numeric not null check(amount>0),status text not null default 'submitted' check(status in('submitted','matched','rejected')),created_by uuid references auth.users(id),approved_by uuid references auth.users(id),approved_at timestamptz,created_at timestamptz not null default now(),unique(order_id,invoice_number));
alter table public.purchase_orders add column if not exists created_by uuid references auth.users(id);
alter table public.purchase_orders add column if not exists approved_by uuid references auth.users(id);
alter table public.purchase_orders add column if not exists approved_at timestamptz;
alter table public.purchase_requisitions add column if not exists approved_by uuid references auth.users(id);
alter table public.purchase_requisitions add column if not exists approved_at timestamptz;
alter table public.accommodation_applications add column if not exists created_by uuid references auth.users(id);
alter table public.accommodation_allocations add column if not exists invoice_id152 uuid references public.student_invoices(id);
alter table public.leave_requests add column if not exists entitlement_year152 uuid references public.academic_years(id);

create or replace function public.unimis_employee_allowed152(p_inst uuid) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.unimis_effective_memberships116 m join public.roles r on r.id=m.role_id where m.user_id=auth.uid() and m.institution_id=p_inst and m.status='active' and r.is_active)$$;
-- Role membership is evaluated on the server for the selected institution. Technical operators have no implicit school powers.
create or replace function public.unimis_operations_allowed152(p_inst uuid,p_domain text,p_write boolean default false)
returns boolean language sql stable security definer set search_path='' as $$
select (not p_write or not exists(select 1 from public.unimis_effective_memberships116 a join public.roles ar on ar.id=a.role_id where a.user_id=auth.uid() and a.institution_id=p_inst and a.status='active' and ar.code='auditor')) and exists(select 1 from public.unimis_effective_memberships116 m join public.roles r on r.id=m.role_id and (r.institution_id=m.institution_id or r.institution_id is null) where m.user_id=auth.uid() and m.institution_id=p_inst and m.status='active' and r.is_active and
(r.code='owner' or (not p_write and r.code='auditor') or
(p_domain='hr' and r.code='hr_officer') or(p_domain='procurement' and r.code in('procurement_officer','finance_officer')) or(p_domain='hostel' and r.code in('accommodation_officer','finance_officer')) or(p_domain='payroll' and r.code in('payroll_officer','finance_officer')) or(p_domain='library' and r.code='librarian')));
$$;
-- Procurement is a school operational role; assigning it still uses the existing protected approval mechanism.
insert into public.roles(institution_id,name,code,is_active) select i.id,'Procurement Officer','procurement_officer',true from public.institutions i where not exists(select 1 from public.roles r where r.institution_id=i.id and r.code='procurement_officer');

-- Configuration is an immutable whitelist, never supplied by clients.
create or replace function public.unimis_operations_config152() returns jsonb language sql immutable set search_path='' as $$select '{"staff": {"table": "staff", "domain": "hr", "fields": ["staff_number", "first_name", "last_name", "email", "phone", "user_id", "department_id", "job_title", "hire_date", "staff_category"], "status": "employment_status", "flow": {"active": ["suspended", "leave", "retired", "resigned", "terminated", "inactive"], "probation": ["active", "suspended"], "suspended": ["active"], "leave": ["active"], "inactive": ["active"]}}, "jobs": {"table": "unimis_jobs152", "domain": "hr", "fields": ["title", "department_id", "positions", "closing_date", "description", "requirements"], "status": "status", "flow": {"draft": ["open", "cancelled"], "open": ["closed", "cancelled"]}}, "candidates": {"table": "unimis_candidates152", "domain": "hr", "fields": ["job_id", "first_name", "last_name", "email", "phone", "evidence"], "status": "status", "flow": {"applied": ["shortlisted", "rejected"], "shortlisted": ["interviewed", "rejected"], "interviewed": ["offered", "rejected"], "offered": ["hired", "rejected"]}}, "leave_types": {"table": "leave_types", "domain": "hr", "fields": ["name", "code", "description", "default_days", "is_paid"], "status": "status", "flow": {"active": ["inactive"], "inactive": ["active"]}}, "balances": {"table": "staff_leave_balances", "domain": "hr", "fields": ["staff_id", "leave_type_id", "academic_year_id", "opening_balance", "accrued_days", "adjusted_days"], "status": null, "flow": {}}, "leave": {"table": "leave_requests", "domain": "hr", "fields": ["staff_id", "leave_type_id", "start_date", "end_date", "reason"], "status": "status", "flow": {"submitted": ["approved", "rejected", "cancelled"], "approved": ["cancelled", "completed"]}}, "sites": {"table": "unimis_sites152", "domain": "hr", "fields": ["name", "latitude", "longitude", "radius_m", "require_gps", "nfc_token", "start_time", "grace_minutes", "timezone"], "status": null, "flow": {}}, "attendance": {"table": "unimis_staff_attendance152", "domain": "hr", "fields": [], "status": "status", "flow": {}}, "exceptions": {"table": "unimis_attendance_exceptions152", "domain": "hr", "fields": ["staff_id", "work_date", "requested_in", "requested_out", "reason"], "status": "status", "flow": {"submitted": ["approved", "rejected"]}}, "performance": {"table": "unimis_performance152", "domain": "hr", "fields": ["staff_id", "period_start", "period_end", "model", "kpi_score", "competency_score", "kpi_weight", "evidence", "goals", "development_plan"], "status": "status", "flow": {"draft": ["submitted"], "submitted": ["approved", "returned"], "returned": ["submitted"], "approved": ["acknowledged"]}}, "suppliers": {"table": "suppliers", "domain": "procurement", "fields": ["name", "contact_person", "email", "phone", "address"], "status": "status", "flow": {"active": ["inactive"], "inactive": ["active"]}}, "requisitions": {"table": "purchase_requisitions", "domain": "procurement", "fields": ["department_id", "purpose"], "status": "status", "flow": {"draft": ["submitted", "cancelled"], "submitted": ["approved", "rejected"], "approved": ["cancelled"]}}, "req_items": {"table": "unimis_requisition_items152", "domain": "procurement", "fields": ["requisition_id", "description", "quantity", "unit_cost"], "status": null, "flow": {}}, "orders": {"table": "purchase_orders", "domain": "procurement", "fields": ["supplier_id", "requisition_id", "currency_code"], "status": "status", "flow": {"draft": ["approved", "cancelled"], "approved": ["sent", "cancelled"]}}, "receipts": {"table": "unimis_goods_receipts152", "domain": "procurement", "fields": ["order_id", "order_item_id", "quantity", "delivery_reference", "inspection_notes"], "status": "status", "flow": {"draft": ["accepted", "rejected"]}}, "supplier_invoices": {"table": "unimis_supplier_invoices152", "domain": "procurement", "fields": ["order_id", "invoice_number", "invoice_date", "amount"], "status": "status", "flow": {"submitted": ["matched", "rejected"]}}, "facilities": {"table": "accommodation_facilities", "domain": "hostel", "fields": ["name", "code", "gender_policy", "location", "description"], "status": "status", "flow": {"active": ["maintenance", "closed", "inactive"], "maintenance": ["active"], "closed": ["active"], "inactive": ["active"]}}, "rooms": {"table": "accommodation_rooms", "domain": "hostel", "fields": ["facility_id", "room_number", "floor_number", "room_type", "capacity"], "status": "status", "flow": {"available": ["maintenance", "closed"], "full": ["maintenance"], "maintenance": ["available"], "closed": ["available"]}}, "beds": {"table": "accommodation_beds", "domain": "hostel", "fields": ["room_id", "bed_code"], "status": "status", "flow": {"available": ["maintenance", "inactive"], "maintenance": ["available"], "inactive": ["available"]}}, "hostel_applications": {"table": "accommodation_applications", "domain": "hostel", "fields": ["student_id", "academic_year_id", "academic_period_id", "preferred_facility_id", "special_requirements"], "status": "status", "flow": {"submitted": ["approved", "rejected", "waitlisted", "cancelled"], "waitlisted": ["approved", "rejected", "cancelled"]}}, "allocations": {"table": "accommodation_allocations", "domain": "hostel", "fields": ["application_id", "bed_id"], "status": "allocation_status", "flow": {"allocated": ["checked_in", "cancelled"], "checked_in": ["checked_out"]}}, "charges": {"table": "accommodation_charges", "domain": "hostel", "fields": ["facility_id", "academic_year_id", "academic_period_id", "room_type", "amount", "currency_code"], "status": "status", "flow": {"active": ["inactive"], "inactive": ["active"]}}, "incidents": {"table": "accommodation_incidents", "domain": "hostel", "fields": ["student_id", "incident_type", "description", "action_taken"], "status": null, "flow": {}}, "library_items": {"table": "library_items", "domain": "library", "fields": ["title", "author", "isbn", "publisher", "publication_year", "description"], "status": "status", "flow": {}}, "copies": {"table": "library_copies", "domain": "library", "fields": ["library_item_id", "accession_number", "barcode", "shelf_location"], "status": "availability_status", "flow": {}}, "members": {"table": "library_members", "domain": "library", "fields": ["member_number", "student_id", "staff_id", "member_type", "max_items", "loan_days"], "status": "status", "flow": {}}, "loans": {"table": "library_loans", "domain": "library", "fields": ["member_id", "copy_id"], "status": "loan_status", "flow": {"borrowed": ["returned"], "overdue": ["returned"]}}, "pay_profiles": {"table": "staff_payroll_profiles", "domain": "payroll", "fields": ["staff_id", "basic_salary", "salary_grade", "bank_name", "bank_account_name", "bank_account_number", "effective_from"], "status": "payroll_status", "flow": {"active": ["suspended", "inactive"], "suspended": ["active"], "inactive": ["active"]}}, "pay_components": {"table": "pay_components", "domain": "payroll", "fields": ["name", "code", "component_type", "calculation_type", "percentage_basis", "is_taxable", "is_pensionable"], "status": "status", "flow": {}}, "employee_components": {"table": "staff_pay_components", "domain": "payroll", "fields": ["staff_id", "pay_component_id", "amount", "percentage", "effective_from", "effective_to", "notes"], "status": null, "flow": {}}, "pay_periods": {"table": "payroll_periods", "domain": "payroll", "fields": ["name", "period_start", "period_end", "payment_date"], "status": "status", "flow": {}}, "pay_runs": {"table": "payroll_runs", "domain": "payroll", "fields": ["payroll_period_id"], "status": "status", "flow": {"draft": ["completed", "cancelled"], "completed": ["approved", "cancelled"], "approved": []}}, "payslips": {"table": "payslips", "domain": "payroll", "fields": [], "status": "status", "flow": {}}, "pay_lines": {"table": "payslip_lines", "domain": "payroll", "fields": [], "status": null, "flow": {}}, "objectives": {"table": "unimis_objectives152", "domain": "hr", "fields": ["staff_id", "title", "category", "start_date", "due_date", "target", "actual", "unit", "evidence"], "status": "status", "flow": {"open": ["completed"], "completed": ["accepted", "returned"], "returned": ["completed"]}}}'::jsonb$$;

-- Payroll uses configured fixed/manual and basic-salary percentage components. No legal rates are assumed.
alter table public.payroll_runs add column if not exists currency152 text not null default 'GHS';
alter table public.payroll_runs add column if not exists journal_id152 uuid references public.finance_journals(id);
alter table public.payroll_runs add column if not exists expense_id152 uuid references public.finance_expenses(id);

create or replace function public.unimis_operations_workspace152(p_inst uuid,p_domain text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare cfg jsonb:=public.unimis_operations_config152(); k text; v jsonb; result jsonb:='{}'; rows jsonb; me uuid; self_only boolean;
begin
 select id into me from public.staff where institution_id=p_inst and user_id=auth.uid() and public.unimis_employee_allowed152(p_inst) and employment_status in('active','probation','leave');
 self_only:=p_domain='self';
 if self_only and me is null then raise exception 'Ask HR to link your active employee record to your school login'; end if;
 if not self_only and not public.unimis_operations_allowed152(p_inst,p_domain,false) then raise exception 'This school workspace requires the relevant operational role. A school Administrator or Registrar is not automatically an HR, procurement or hostel officer'; end if;
 for k,v in select * from jsonb_each(cfg) loop
  if (not self_only and v->>'domain'=p_domain) or (self_only and k in('leave_types','balances','leave','attendance','exceptions','performance','payslips','objectives')) then
   if self_only and k<>'leave_types' then
    execute format('select coalesce(jsonb_agg(x),''[]'') from (select to_jsonb(t) x from public.%I t where institution_id=$1 and staff_id=$2 order by created_at desc limit 2000)t',v->>'table') into rows using p_inst,me;
    if k='payslips' then select coalesce(jsonb_agg(x),'[]') into rows from jsonb_array_elements(rows) x where x->>'status' in('approved','paid'); end if;
    if k='performance' then select coalesce(jsonb_agg(x),'[]') into rows from jsonb_array_elements(rows) x where x->>'status' in('approved','acknowledged'); end if;
   else
    execute format('select coalesce(jsonb_agg(x),''[]'') from (select to_jsonb(t) x from public.%I t where institution_id=$1 order by created_at desc limit 2000)t',v->>'table') into rows using p_inst;
   end if;
   result:=result||jsonb_build_object(k,rows);
  end if;
 end loop;
 result:=result||jsonb_build_object('years',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name)),'[]') from public.academic_years where institution_id=p_inst),'periods',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'academic_year_id',academic_year_id)),'[]') from public.academic_periods where institution_id=p_inst),'departments',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name)),'[]') from public.departments where institution_id=p_inst),'me',me,'can_write',not self_only and public.unimis_operations_allowed152(p_inst,p_domain,true),'self',self_only,'server_time',now());
 if self_only then
 result:=result||jsonb_build_object('staff',(select jsonb_build_array(jsonb_build_object('id',id,'first_name',first_name,'last_name',last_name,'staff_number',staff_number)) from public.staff where id=me),'sites',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'require_gps',require_gps)),'[]') from public.unimis_sites152 where institution_id=p_inst));
 else
 if p_domain in('hr','library','payroll') then result:=result||jsonb_build_object('staff',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'first_name',first_name,'last_name',last_name,'staff_number',staff_number)),'[]') from public.staff where institution_id=p_inst)); end if;
 if p_domain='hr' then -- HR directory retains full business fields from above; login lookup never exposes Auth secrets.
 execute 'select coalesce(jsonb_agg(to_jsonb(t)),''[]'') from public.staff t where institution_id=$1' into rows using p_inst; result:=jsonb_set(result,'{staff}',rows);
 result:=result||jsonb_build_object('users',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',email)),'[]') from auth.users u where exists(select 1 from public.unimis_effective_memberships116 m where m.user_id=u.id and m.institution_id=p_inst and m.status='active')));
 end if;
 if p_domain in('hostel','library') then result:=result||jsonb_build_object('students',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',concat_ws(' ',student_number,first_name,last_name),'gender',gender)),'[]') from public.students where institution_id=p_inst)); end if;
 if p_domain='payroll' then result:=result||jsonb_build_object('finance_accounts',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',code||' • '||name,'account_type',account_type)),'[]') from public.finance_accounts where institution_id=p_inst and status='active')); end if;
 if p_domain='procurement' then result:=result||jsonb_build_object('order_items',(select coalesce(jsonb_agg(to_jsonb(t)),'[]') from public.unimis_order_items152 t where institution_id=p_inst)); end if;
 end if;
 return result;
end $$;

create or replace function public.unimis_operations_save152(p_inst uuid,p_entity text,p_id uuid default null,p_data jsonb default '{}')
returns uuid language plpgsql security definer set search_path='' as $$
declare cfg jsonb:=public.unimis_operations_config152()->p_entity; tbl text; col text; cols text[]:='{}'; oldrow jsonb; clean jsonb; me uuid; result uuid; allowed boolean; fk record; ref uuid; valid boolean; app public.accommodation_applications%rowtype; bed public.accommodation_beds%rowtype; room public.accommodation_rooms%rowtype; fac public.accommodation_facilities%rowtype; charge public.accommodation_charges%rowtype; invoice uuid; po public.purchase_orders%rowtype; sid uuid;
begin
 if cfg is null or jsonb_typeof(p_data) is distinct from 'object' then raise exception 'Unknown operation'; end if; tbl:=cfg->>'table';
 select id into me from public.staff where user_id=auth.uid() and institution_id=p_inst and public.unimis_employee_allowed152(p_inst) and employment_status in('active','probation','leave');
 allowed:=public.unimis_operations_allowed152(p_inst,cfg->>'domain',true);
 if not allowed and not (me is not null and ((p_entity in('leave','exceptions') and p_id is null) or (p_entity='objectives' and p_id is not null))) then raise exception 'Not authorised to change this school workspace'; end if;
 if p_entity in('attendance','payslips','pay_lines') then raise exception 'Use clock-in or the exception approval process'; end if;
 clean:=p_data;
 for col in select jsonb_object_keys(p_data) loop
  if not (cfg->'fields' ? col) then raise exception 'Field % is not editable',col; end if;
  if p_data->>col is not null and length(p_data->>col)>10000 then raise exception 'Field % exceeds the text limit',col; end if;
  if p_data->>col='' then clean:=jsonb_set(clean,array[col],'null'); end if;
 end loop;
 if not allowed and p_entity<>'objectives' then clean:=clean||jsonb_build_object('staff_id',me); end if;
 if p_id is not null then
 execute format('select to_jsonb(t) from public.%I t where id=$1 and institution_id=$2 for update',tbl) into oldrow using p_id,p_inst;
 if oldrow is null then raise exception 'Record not found in this school'; end if;
 if cfg->>'status' is not null and p_entity not in('staff','leave_types','facilities','rooms','beds','charges','copies','members','library_items','suppliers') and oldrow->>(cfg->>'status') not in('draft','returned','applied','open') and not (p_entity='candidates' and oldrow->>'status' in('shortlisted','interviewed')) then raise exception 'Submitted/approved records cannot be edited. Use a documented transition'; end if;
 if p_entity='objectives' and not allowed then
  if oldrow->>'staff_id' is distinct from me::text then raise exception 'Not your objective'; end if;
  if exists(select 1 from jsonb_object_keys(clean) k where k not in('actual','evidence')) then raise exception 'Employees can update actual progress and evidence only'; end if;
 end if;
 if p_entity='candidates' and oldrow->>'status' in('shortlisted','interviewed') and exists(select 1 from jsonb_object_keys(clean) k where k<>'evidence' and clean->k is distinct from oldrow->k) then raise exception 'After shortlisting, update interview evidence only'; end if;
 if p_entity='jobs' and oldrow->>'status'<>'draft' then raise exception 'Published vacancy details are frozen; close it and publish a new vacancy'; end if;
 if p_entity='balances' then clean:=clean-'staff_id'-'leave_type_id'-'academic_year_id'; end if;
 end if;
 -- Every foreign school reference is checked, not merely trusted from the dropdown.
 for fk in select a.attname column_name,c.confrelid::regclass::text target from pg_catalog.pg_constraint c join pg_catalog.pg_attribute a on a.attrelid=c.conrelid and a.attnum=c.conkey[1] where c.contype='f' and c.conrelid=('public.'||tbl)::regclass and cardinality(c.conkey)=1 loop
  if clean ? fk.column_name and clean->>fk.column_name is not null then
   ref:=(clean->>fk.column_name)::uuid;
   if fk.target='auth.users' then select exists(select 1 from public.unimis_effective_memberships116 where user_id=ref and institution_id=p_inst and status='active') into valid;
   elsif fk.target='institutions' or fk.target='public.institutions' then valid:=ref=p_inst;
   else execute format('select exists(select 1 from %s where id=$1 and institution_id=$2)',fk.target) into valid using ref,p_inst;
   end if;
   if not valid then raise exception 'Invalid or cross-school reference: %',fk.column_name; end if;
  end if;
 end loop;
 if p_id is not null and p_entity in('beds','rooms','copies','staff') then
  if p_entity='beds' and clean->>'room_id' is distinct from oldrow->>'room_id' then raise exception 'Bed room is immutable; create a new bed'; end if;
  if p_entity='rooms' and clean->>'facility_id' is distinct from oldrow->>'facility_id' then raise exception 'Room facility is immutable'; end if;
  if p_entity='copies' and clean->>'library_item_id' is distinct from oldrow->>'library_item_id' then raise exception 'Copy title is immutable'; end if;
  if p_entity='rooms' and (clean->>'capacity')::integer<(select count(*) from public.accommodation_allocations where room_id=p_id and allocation_status in('allocated','checked_in')) then raise exception 'Capacity cannot fall below active occupancy'; end if;
  if p_entity='staff' and oldrow->>'user_id' is not null and clean->>'user_id' is distinct from oldrow->>'user_id' then raise exception 'Existing login identity cannot be reassigned through HR; use the protected account correction process'; end if;
 end if;
 if p_entity='sites' and not exists(select 1 from pg_catalog.pg_timezone_names where name=clean->>'timezone') then raise exception 'Choose a valid IANA time zone, for example Africa/Accra'; end if;
 if p_entity='leave' then
 perform 1 from public.staff where id=(clean->>'staff_id')::uuid and institution_id=p_inst for update;
 if (clean->>'end_date')::date<(clean->>'start_date')::date then raise exception 'Leave end date precedes start'; end if;
 if exists(select 1 from public.leave_requests where staff_id=(clean->>'staff_id')::uuid and institution_id=p_inst and status in('submitted','approved') and id is distinct from p_id and daterange(start_date,end_date,'[]') && daterange((clean->>'start_date')::date,(clean->>'end_date')::date,'[]')) then raise exception 'Overlapping leave request'; end if;
 clean:=clean||jsonb_build_object('requested_days',(select count(*) from generate_series((clean->>'start_date')::date,(clean->>'end_date')::date,interval '1 day') d where extract(isodow from d)<6),'status','submitted');
 if (clean->>'requested_days')::numeric=0 then raise exception 'Request contains no weekdays. Leave uses Monday–Friday; configure entitlement adjustments for holidays or special schedules'; end if;
 end if;
 if p_entity='pay_periods' then
 if exists(select 1 from public.payroll_periods where institution_id=p_inst and id is distinct from p_id and status<>'cancelled' and daterange(period_start,period_end,'[]') && daterange((clean->>'period_start')::date,(clean->>'period_end')::date,'[]')) then raise exception 'Payroll period overlaps an existing active period'; end if;
 end if;
 if p_entity='employee_components' then
 perform 1 from public.staff where id=(clean->>'staff_id')::uuid and institution_id=p_inst for update;
 if exists(select 1 from public.staff_pay_components where institution_id=p_inst and id is distinct from p_id and staff_id=(clean->>'staff_id')::uuid and pay_component_id=(clean->>'pay_component_id')::uuid and is_active and daterange(effective_from,coalesce(effective_to,'infinity'::date),'[]') && daterange((clean->>'effective_from')::date,coalesce((clean->>'effective_to')::date,'infinity'::date),'[]')) then raise exception 'Employee component overlaps another active assignment'; end if;
 end if;
 if p_entity='pay_runs' then
 if p_id is not null then raise exception 'Payroll runs cannot be edited after creation'; end if;
 perform 1 from public.payroll_periods where id=(clean->>'payroll_period_id')::uuid and institution_id=p_inst and status='draft' for update;
 if not found then raise exception 'Choose a draft payroll period'; end if;
 if exists(select 1 from public.payroll_runs where payroll_period_id=(clean->>'payroll_period_id')::uuid and status<>'cancelled') then raise exception 'Period already has an active payroll run'; end if;
 if exists(select 1 from public.payroll_settings where institution_id=p_inst and currency_code<>'GHS' and is_active) then raise exception 'This payroll posting workflow supports GHS. Configure a currency-aware treasury workflow for other currencies'; end if;
 clean:=clean||jsonb_build_object('run_number','PAY-'||substr(gen_random_uuid()::text,1,12));
 end if;
 if p_entity='requisitions' and p_id is null then clean:=clean||jsonb_build_object('requisition_no','REQ-'||substr(gen_random_uuid()::text,1,12),'requested_by',auth.uid()); end if;
 if p_entity='req_items' then
 perform 1 from public.purchase_requisitions where id=(clean->>'requisition_id')::uuid and institution_id=p_inst and status='draft' for update;
 if not found then raise exception 'Items can only be changed on a draft requisition'; end if;
 if p_id is not null and oldrow->>'requisition_id' is distinct from clean->>'requisition_id' then raise exception 'An item cannot be moved between requisitions'; end if;
 end if;
 if p_entity='orders' then
 if p_id is not null then raise exception 'Cancel the draft and recreate an order to change its supplier or source'; end if;
 perform 1 from public.purchase_requisitions where id=(clean->>'requisition_id')::uuid and institution_id=p_inst and status='approved' for update;
 if not found then raise exception 'Select an approved requisition'; end if;
 if exists(select 1 from public.purchase_orders where requisition_id=(clean->>'requisition_id')::uuid and status<>'cancelled') then raise exception 'An active purchase order already exists'; end if;
 clean:=clean||jsonb_build_object('po_number','PO-'||substr(gen_random_uuid()::text,1,12),'total_amount',(select sum(line_total) from public.unimis_requisition_items152 where requisition_id=(clean->>'requisition_id')::uuid));
 end if;
 if p_entity='candidates' and p_id is null then perform 1 from public.unimis_jobs152 where id=(clean->>'job_id')::uuid and status='open' and closing_date>=current_date; if not found then raise exception 'Vacancy is closed or has passed its closing date'; end if; end if;
 if clean ? 'academic_period_id' and clean->>'academic_period_id' is not null and clean ? 'academic_year_id' and not exists(select 1 from public.academic_periods where id=(clean->>'academic_period_id')::uuid and academic_year_id=(clean->>'academic_year_id')::uuid and institution_id=p_inst) then raise exception 'Semester does not belong to the selected year'; end if;
 if p_entity='allocations' then
 if p_id is not null then raise exception 'Use check-in, check-out or cancellation'; end if;
 select * into app from public.accommodation_applications where id=(clean->>'application_id')::uuid and institution_id=p_inst for update;
 if app.status<>'approved' then raise exception 'Application must be approved first'; end if;
 perform 1 from public.students where id=app.student_id for update;
 select * into bed from public.accommodation_beds where id=(clean->>'bed_id')::uuid and institution_id=p_inst for update;
 select * into room from public.accommodation_rooms where id=bed.room_id and institution_id=p_inst for update;
 select * into fac from public.accommodation_facilities where id=room.facility_id and institution_id=p_inst;
 if bed.status<>'available' or room.status not in('available','full') or fac.status<>'active' then raise exception 'Selected bed or facility is unavailable'; end if;
 if exists(select 1 from public.accommodation_allocations where institution_id=p_inst and allocation_status in('allocated','checked_in') and (bed_id=bed.id or student_id=app.student_id)) then raise exception 'Bed or student already has an active allocation; check out the previous allocation'; end if;
 if (select count(*) from public.accommodation_allocations where room_id=room.id and allocation_status in('allocated','checked_in'))>=room.capacity then raise exception 'Room capacity reached'; end if;
 if fac.gender_policy in('male','female') and not exists(select 1 from public.students where id=app.student_id and lower(gender)=fac.gender_policy) then raise exception 'Student does not meet the facility gender policy'; end if;
 select * into charge from public.accommodation_charges where institution_id=p_inst and facility_id=fac.id and academic_year_id=app.academic_year_id and academic_period_id is not distinct from app.academic_period_id and status='active' and (room_type=room.room_type or room_type is null) order by (room_type is not null) desc,created_at desc limit 1;
 if charge.id is null or charge.amount<=0 then raise exception 'Configure a positive tariff for this facility, year and semester before allocating'; end if;
 invoice:=gen_random_uuid();
 insert into public.student_invoices(id,institution_id,student_id,academic_year_id,academic_period_id,invoice_number,currency_code,subtotal,total_amount,balance,status,notes,created_by) values(invoice,p_inst,app.student_id,app.academic_year_id,app.academic_period_id,'HOSTEL-'||substr(invoice::text,1,12),charge.currency_code,charge.amount,charge.amount,charge.amount,'unpaid','Hostel allocation: '||fac.name||' / '||room.room_number||' / '||bed.bed_code,auth.uid());
 insert into public.student_invoice_items(institution_id,invoice_id,description,unit_amount,line_total) values(p_inst,invoice,'Accommodation: '||fac.name||' / '||room.room_number,charge.amount,charge.amount);
 clean:=clean||jsonb_build_object('student_id',app.student_id,'academic_year_id',app.academic_year_id,'academic_period_id',app.academic_period_id,'facility_id',fac.id,'room_id',room.id,'allocated_by',auth.uid(),'invoice_id152',invoice);
 update public.accommodation_beds set status='reserved' where id=bed.id;
 if (select count(*)+1 from public.accommodation_allocations where room_id=room.id and allocation_status in('allocated','checked_in'))>=room.capacity then update public.accommodation_rooms set status='full' where id=room.id; end if;
 end if;
 if p_entity='loans' then
 if p_id is not null then raise exception 'Use Return'; end if;
 perform 1 from public.library_members where id=(clean->>'member_id')::uuid and institution_id=p_inst and status='active' and (expires_at is null or expires_at>now()) for update;
 if not found then raise exception 'Member is inactive or expired'; end if;
 perform 1 from public.library_copies where id=(clean->>'copy_id')::uuid and institution_id=p_inst and availability_status='available' for update;
 if not found then raise exception 'Copy is unavailable'; end if;
 if (select count(*) from public.library_loans where member_id=(clean->>'member_id')::uuid and loan_status in('borrowed','overdue'))>=(select max_items from public.library_members where id=(clean->>'member_id')::uuid) then raise exception 'Member borrowing limit reached'; end if;
 clean:=clean||jsonb_build_object('due_at',now()+(select loan_days from public.library_members where id=(clean->>'member_id')::uuid)*interval '1 day','issued_by',auth.uid());
 update public.library_copies set availability_status='borrowed' where id=(clean->>'copy_id')::uuid;
 end if;
 clean:=clean||jsonb_build_object('institution_id',p_inst);
 if p_id is null then
 if exists(select 1 from information_schema.columns where table_schema='public' and table_name=tbl and column_name='created_by') then clean:=clean||jsonb_build_object('created_by',auth.uid()); end if;
 select array_agg(key order by key) into cols from jsonb_object_keys(clean) key;
 execute format('insert into public.%1$I (%2$s) select %2$s from jsonb_populate_record(null::public.%1$I,$1) returning id',tbl,(select string_agg(format('%I',x),',') from unnest(cols)x)) into result using clean;
 else
 select array_agg(key order by key) into cols from jsonb_object_keys(clean) key where key<>'institution_id';
 execute format('update public.%1$I t set (%2$s)=(select %2$s from jsonb_populate_record(null::public.%1$I,$1)) where id=$2 and institution_id=$3 returning id',tbl,(select string_agg(format('%I',x),',') from unnest(cols)x)) into result using clean,p_id,p_inst;
 end if;
 if p_entity='balances' and exists(select 1 from public.staff_leave_balances where id=result and remaining_days<0) then raise exception 'Entitlement cannot be reduced below leave already used'; end if;
 if p_entity='req_items' then update public.purchase_requisitions set estimated_total=(select coalesce(sum(line_total),0) from public.unimis_requisition_items152 where requisition_id=(clean->>'requisition_id')::uuid) where id=(clean->>'requisition_id')::uuid; end if;
 if p_entity='orders' then
 insert into public.unimis_order_items152(institution_id,order_id,description,quantity,unit_cost) select p_inst,result,description,quantity,unit_cost from public.unimis_requisition_items152 where requisition_id=(clean->>'requisition_id')::uuid;
 update public.purchase_requisitions set status='ordered' where id=(clean->>'requisition_id')::uuid;
 end if;
 insert into public.unimis_operations_events152(institution_id,actor_id,entity,record_id,action,changed_fields) values(p_inst,auth.uid(),p_entity,result,case when p_id is null then 'created' else 'edited' end,cols);
 return result;
end $$;
-- Replace the old one-way leave deduction with locked, reversible entitlement accounting.
create or replace function public.apply_leave_balance() returns trigger language plpgsql security definer set search_path='' as $$
declare yr uuid; bal public.staff_leave_balances%rowtype;
begin
 if new.status='approved' and old.status is distinct from new.status then
  select id into yr from public.academic_years where institution_id=new.institution_id and is_current=true order by created_at desc limit 1;
  select * into bal from public.staff_leave_balances where institution_id=new.institution_id and staff_id=new.staff_id and leave_type_id=new.leave_type_id and academic_year_id=yr for update;
  if bal.id is null then raise exception 'No leave entitlement exists for the current academic year'; end if;
  if bal.remaining_days<new.requested_days then raise exception 'Insufficient leave entitlement'; end if;
  new.entitlement_year152:=yr;
  update public.staff_leave_balances set used_days=used_days+new.requested_days where id=bal.id;
 elsif old.status in('approved','completed') and new.status='cancelled' then
  update public.staff_leave_balances set used_days=greatest(used_days-old.requested_days,0) where institution_id=old.institution_id and staff_id=old.staff_id and leave_type_id=old.leave_type_id and academic_year_id=old.entitlement_year152;
 end if;
 return new;
end $$;
drop trigger if exists trg_apply_leave_balance on public.leave_requests;
create trigger trg_apply_leave_balance before update of status on public.leave_requests for each row execute function public.apply_leave_balance();

create or replace function public.unimis_operations_decide152(p_inst uuid,p_entity text,p_id uuid,p_action text,p_note text)
returns void language plpgsql security definer set search_path='' as $$
declare cfg jsonb:=public.unimis_operations_config152()->p_entity; oldrow jsonb; previous_state text; tbl text; sid uuid; creator uuid; ownstaff uuid; changes jsonb; need_approval boolean; orderrow public.purchase_orders%rowtype; item public.unimis_order_items152%rowtype; qty numeric; inv public.student_invoices%rowtype; bedid uuid; facid uuid; staffnew uuid; job public.unimis_jobs152%rowtype; ex public.unimis_attendance_exceptions152%rowtype;
begin
 if cfg is null or cfg->>'status' is null then raise exception 'Unknown workflow'; end if;
 tbl:=cfg->>'table';
 execute format('select to_jsonb(t) from public.%I t where id=$1 and institution_id=$2 for update',tbl) into oldrow using p_id,p_inst;
 if oldrow is null then raise exception 'Record not found in this school'; end if;
 previous_state:=oldrow->>(cfg->>'status');
 if not coalesce(cfg->'flow'->previous_state ? p_action,false) then raise exception 'Invalid transition: % to % ',previous_state,p_action; end if;
 if length(trim(coalesce(p_note,'')))<5 then raise exception 'Record a decision or action note of at least five characters'; end if;
 select id into ownstaff from public.staff where user_id=auth.uid() and institution_id=p_inst;
 if not public.unimis_operations_allowed152(p_inst,cfg->>'domain',true) then
  if not (ownstaff is not null and oldrow->>'staff_id'=ownstaff::text and ((p_entity='leave' and p_action='cancelled' and previous_state='submitted') or (p_entity='performance' and p_action='acknowledged') or (p_entity='objectives' and p_action='completed'))) then raise exception 'Not authorised'; end if;
 end if;
 need_approval:=p_action in('approved','accepted','matched','offered','hired');
 creator:=coalesce((oldrow->>'created_by')::uuid,(oldrow->>'requested_by')::uuid);
 if need_approval and (creator=auth.uid() or oldrow->>'staff_id'=ownstaff::text) then raise exception 'Approval requires someone other than the preparer or employee'; end if;
 changes:=jsonb_build_object(cfg->>'status',p_action);
 if need_approval and exists(select 1 from information_schema.columns where table_schema='public' and table_name=tbl and column_name='approved_by') then changes:=changes||jsonb_build_object('approved_by',auth.uid(),'approved_at',now()); end if;
 if p_entity in('facilities','rooms','beds') and p_action in('maintenance','closed','inactive') and exists(select 1 from public.accommodation_allocations where institution_id=p_inst and allocation_status in('allocated','checked_in') and ((p_entity='facilities' and facility_id=p_id) or(p_entity='rooms' and room_id=p_id) or(p_entity='beds' and bed_id=p_id))) then raise exception 'Check out or cancel active allocations before closing this inventory'; end if;
 if p_entity='staff' and oldrow->>'user_id'=auth.uid()::text then raise exception 'Another HR officer or Owner must change your employment status'; end if;
 if p_entity='leave' and p_action='rejected' then changes:=changes||jsonb_build_object('rejection_reason',p_note); end if;
 if p_entity='pay_runs' then perform public.unimis_payroll_transition152(p_inst,p_id,p_action); end if;
 if p_entity='performance' and p_action='acknowledged' then
 if oldrow->>'staff_id' is distinct from ownstaff::text then raise exception 'Only the reviewed employee can acknowledge'; end if;
 changes:=changes||jsonb_build_object('employee_response',p_note);
 end if;
 if p_entity='requisitions' and p_action in('submitted','approved') then
 if not exists(select 1 from public.unimis_requisition_items152 where requisition_id=p_id) or (oldrow->>'estimated_total')::numeric<=0 then raise exception 'Add priced requisition items first'; end if;
 end if;
 if p_entity='orders' and p_action='cancelled' then update public.purchase_requisitions set status='approved' where id=(oldrow->>'requisition_id')::uuid and institution_id=p_inst; end if;
 if p_entity='orders' and p_action='approved' then
 if not exists(select 1 from public.unimis_order_items152 where order_id=p_id) then raise exception 'No purchase order items'; end if;
 end if;
 if p_entity='receipts' and p_action='accepted' then
 select * into orderrow from public.purchase_orders where id=(oldrow->>'order_id')::uuid and institution_id=p_inst for update;
 select * into item from public.unimis_order_items152 where id=(oldrow->>'order_item_id')::uuid and institution_id=p_inst for update;
 if item.order_id<>orderrow.id or orderrow.status not in('sent','part_received') then raise exception 'Receipt item must belong to a sent or partly received order'; end if;
 select coalesce(sum(quantity),0)+(oldrow->>'quantity')::numeric into qty from public.unimis_goods_receipts152 where order_item_id=item.id and status='accepted';
 if qty>item.quantity then raise exception 'Receipt exceeds ordered quantity'; end if;
 end if;
 if p_entity='supplier_invoices' and p_action='matched' then
 select * into orderrow from public.purchase_orders where id=(oldrow->>'order_id')::uuid and institution_id=p_inst for update;
 if orderrow.status<>'received' then raise exception 'All ordered goods must be accepted before full invoice matching'; end if;
 if (oldrow->>'amount')::numeric<>orderrow.total_amount then raise exception 'Invoice value differs from the purchase order'; end if;
 if exists(select 1 from public.unimis_supplier_invoices152 where order_id=orderrow.id and status='matched' and id<>p_id) then raise exception 'Order already has a matched invoice'; end if;
 end if;
 if p_entity='exceptions' and p_action='approved' then
 select * into ex from public.unimis_attendance_exceptions152 where id=p_id;
 if ex.requested_in::date<>ex.work_date or (ex.requested_out is not null and ex.requested_out-ex.requested_in>interval '24 hours') then raise exception 'Check attendance correction dates and duration'; end if;
 insert into public.unimis_staff_attendance152(institution_id,staff_id,work_date,check_in,check_out,method,status) values(p_inst,ex.staff_id,ex.work_date,ex.requested_in,ex.requested_out,'exception','corrected') on conflict(staff_id,work_date) do update set check_in=excluded.check_in,check_out=excluded.check_out,method='exception',status='corrected';
 end if;
 if p_entity='candidates' and p_action in('interviewed','offered') and length(trim(coalesce(oldrow->>'evidence','')))<10 then raise exception 'Record qualifications or interview evidence before this decision'; end if;
 if p_entity='candidates' and p_action='hired' then
 select * into job from public.unimis_jobs152 where id=(oldrow->>'job_id')::uuid for update;
 if (select count(*) from public.unimis_candidates152 where job_id=job.id and status='hired')>=job.positions then raise exception 'All vacancy positions are filled'; end if;
 staffnew:=gen_random_uuid();
 insert into public.staff(id,institution_id,staff_number,first_name,last_name,email,phone,department_id,job_title,hire_date) values(staffnew,p_inst,'STAFF-'||substr(staffnew::text,1,10),oldrow->>'first_name',oldrow->>'last_name',oldrow->>'email',oldrow->>'phone',job.department_id,job.title,current_date);
 changes:=changes||jsonb_build_object('staff_id',staffnew);
 end if;
 if p_entity='hostel_applications' and p_action in('approved','rejected','waitlisted') then changes:=changes||jsonb_build_object('reviewed_by',auth.uid(),'reviewed_at',now(),'notes',p_note); end if;
 if p_entity='allocations' then
 bedid:=(oldrow->>'bed_id')::uuid;
 perform 1 from public.accommodation_beds where id=bedid for update;
 if p_action='checked_in' then changes:=changes||jsonb_build_object('check_in_at',now()); update public.accommodation_beds set status='occupied' where id=bedid;
 elsif p_action in('checked_out','cancelled') then
  if p_action='cancelled' then
   select * into inv from public.student_invoices where id=(oldrow->>'invoice_id152')::uuid and institution_id=p_inst for update;
   if inv.amount_paid>0 or exists(select 1 from public.student_payments where invoice_id=inv.id and status='completed') then raise exception 'Paid accommodation must be adjusted through Accounts before cancellation'; end if;
   if inv.id is not null then update public.student_invoices set status='cancelled',notes=coalesce(notes,'')||E'\nAllocation cancelled: '||p_note where id=inv.id; end if;
  else changes:=changes||jsonb_build_object('check_out_at',now()); end if;
  update public.accommodation_beds set status='available' where id=bedid;
  update public.accommodation_rooms set status='available' where id=(oldrow->>'room_id')::uuid and status='full';
 end if;
 end if;
 if p_entity='loans' and p_action='returned' then changes:=changes||jsonb_build_object('returned_at',now(),'received_by',auth.uid()); update public.library_copies set availability_status='available' where id=(oldrow->>'copy_id')::uuid; end if;
 execute format('update public.%1$I t set (%2$s)=(select %2$s from jsonb_populate_record(null::public.%1$I,$1)) where id=$2 and institution_id=$3',tbl,(select string_agg(format('%I',key),',') from jsonb_object_keys(changes) key)) using changes,p_id,p_inst;
 if p_entity='receipts' and p_action='accepted' then
 update public.purchase_orders set status=case when not exists(select 1 from public.unimis_order_items152 oi where oi.order_id=orderrow.id and oi.quantity>(select coalesce(sum(g.quantity),0) from public.unimis_goods_receipts152 g where g.order_item_id=oi.id and g.status='accepted')) then 'received' else 'part_received' end where id=orderrow.id;
 end if;
 insert into public.unimis_operations_events152(institution_id,actor_id,entity,record_id,action,note) values(p_inst,auth.uid(),p_entity,p_id,p_action,p_note);
end $$;

create or replace function public.unimis_attendance_qr152(p_inst uuid,p_site uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare tok uuid; expiry timestamptz:=now()+interval '90 seconds';
begin
 if not public.unimis_operations_allowed152(p_inst,'hr',true) then raise exception 'HR or Owner must issue the attendance QR'; end if;
 perform 1 from public.unimis_sites152 where id=p_site and institution_id=p_inst; if not found then raise exception 'Invalid site'; end if;
 delete from public.unimis_attendance_tokens152 where site_id=p_site and expires_at<now();
 insert into public.unimis_attendance_tokens152(institution_id,site_id,expires_at,created_by) values(p_inst,p_site,expiry,auth.uid()) returning token into tok;
 return jsonb_build_object('token',tok,'expires_at',expiry);
end $$;

create or replace function public.unimis_attendance_clock152(p_inst uuid,p_site uuid,p_method text,p_token text,p_direction text,p_lat double precision default null,p_lon double precision default null,p_accuracy double precision default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare me public.staff%rowtype; site public.unimis_sites152%rowtype; day date; att public.unimis_staff_attendance152%rowtype; distance double precision; late integer;
begin
 select * into me from public.staff where institution_id=p_inst and user_id=auth.uid() and public.unimis_employee_allowed152(p_inst) and employment_status in('active','probation');
 if me.id is null then raise exception 'No active linked staff record'; end if;
 perform 1 from public.staff where id=me.id for update;
 select * into site from public.unimis_sites152 where id=p_site and institution_id=p_inst;
 if site.id is null then raise exception 'Invalid attendance site'; end if;
 if p_direction not in('in','out') then raise exception 'Invalid clock direction'; end if;
 if p_method='qr' then
  if not exists(select 1 from public.unimis_attendance_tokens152 where institution_id=p_inst and site_id=p_site and token::text=p_token and expires_at>now()) then raise exception 'QR code has expired; scan the current code displayed by HR'; end if;
 elsif p_method='nfc' then
  if site.nfc_token is distinct from p_token then raise exception 'Wrong NFC campus tag'; end if;
 else raise exception 'Use QR, NFC or a reviewed attendance exception'; end if;
 if site.require_gps then
  if p_lat is null or p_lon is null or p_accuracy is null or p_lat not between -90 and 90 or p_lon not between -180 and 180 or p_accuracy not between 0 and least(site.radius_m,100) then raise exception 'Accurate location permission is required at this site'; end if;
  distance:=6371000*2*asin(least(1,sqrt(power(sin(radians(p_lat-site.latitude)/2),2)+cos(radians(site.latitude))*cos(radians(p_lat))*power(sin(radians(p_lon-site.longitude)/2),2))));
  if distance>site.radius_m then raise exception 'Outside attendance geofence (% metres away)',round(distance::numeric); end if;
 end if;
 day:=(now() at time zone site.timezone)::date;
 select * into att from public.unimis_staff_attendance152 where staff_id=me.id and work_date=day for update;
 if exists(select 1 from public.leave_requests where staff_id=me.id and status='approved' and day between start_date and end_date) then raise exception 'Approved leave covers today; resolve the leave status with HR first'; end if;
 if p_direction='in' then
  if att.id is not null then raise exception 'Already checked in today'; end if;
  late:=greatest(0,floor(extract(epoch from ((now() at time zone site.timezone)::time-site.start_time))/60)::integer-site.grace_minutes);
  insert into public.unimis_staff_attendance152(institution_id,staff_id,site_id,work_date,check_in,method,latitude,longitude,accuracy_m,late_minutes) values(p_inst,me.id,p_site,day,now(),p_method,case when site.require_gps then p_lat end,case when site.require_gps then p_lon end,case when site.require_gps then p_accuracy end,late) returning * into att;
 else
  if att.id is null then raise exception 'Check in first'; end if;
  if att.check_out is not null then raise exception 'Already checked out'; end if;
  if att.site_id<>p_site then raise exception 'Check out at your check-in site'; end if;
  update public.unimis_staff_attendance152 set check_out=now() where id=att.id returning * into att;
 end if;
 insert into public.unimis_operations_events152(institution_id,actor_id,entity,record_id,action) values(p_inst,auth.uid(),'attendance',att.id,'clock_'||p_direction);
 return to_jsonb(att);
end $$;

create or replace function public.unimis_operations_history152(p_inst uuid,p_entity text,p_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare cfg jsonb:=public.unimis_operations_config152()->p_entity; ownerid uuid; me uuid;
begin
 if cfg is null then raise exception 'Invalid entity'; end if;
 if not public.unimis_operations_allowed152(p_inst,cfg->>'domain',false) then
  if p_entity not in('leave','exceptions','attendance','performance','payslips','objectives') then raise exception 'Not authorised'; end if;
  select id into me from public.staff where institution_id=p_inst and user_id=auth.uid() and public.unimis_employee_allowed152(p_inst);
  execute format('select staff_id from public.%I where institution_id=$1 and id=$2',cfg->>'table') into ownerid using p_inst,p_id;
  if me is null or ownerid is distinct from me then raise exception 'Not authorised'; end if;
 end if;
 return(select coalesce(jsonb_agg(jsonb_build_object('action',e.action,'note',e.note,'changed_fields',e.changed_fields,'created_at',e.created_at,'actor',coalesce(u.email,e.actor_id::text)) order by e.created_at),'[]') from public.unimis_operations_events152 e left join auth.users u on u.id=e.actor_id where e.institution_id=p_inst and e.entity=p_entity and e.record_id=p_id);
end $$;

create or replace function public.unimis_payroll_transition152(p_inst uuid,p_run uuid,p_action text)
returns void language plpgsql security definer set search_path='' as $$
declare run public.payroll_runs%rowtype; period public.payroll_periods%rowtype; profile public.staff_payroll_profiles%rowtype; component record; amount numeric; slip uuid; gross numeric; deductions numeric; employer numeric; totalcount integer:=0;
begin
 if not public.unimis_operations_allowed152(p_inst,'payroll',true) then raise exception 'Payroll access required'; end if;
 select * into run from public.payroll_runs where id=p_run and institution_id=p_inst for update;
 if run.id is null then raise exception 'Payroll run not found'; end if;
 select * into period from public.payroll_periods where id=run.payroll_period_id and institution_id=p_inst for update;
 if p_action='completed' then
  if run.status<>'draft' then raise exception 'Only a draft payroll can be calculated'; end if;
  for profile in select p.* from public.staff_payroll_profiles p join public.staff s on s.id=p.staff_id and s.institution_id=p_inst where p.institution_id=p_inst and p.payroll_status='active' and s.employment_status in('active','probation','leave') and p.effective_from<=period.period_end and (p.effective_to is null or p.effective_to>=period.period_start) loop
   totalcount:=totalcount+1;gross:=profile.basic_salary;deductions:=0;employer:=0;slip:=gen_random_uuid();
   insert into public.payslips(id,institution_id,payroll_run_id,staff_id,basic_salary) values(slip,p_inst,p_run,profile.staff_id,profile.basic_salary);
   insert into public.payslip_lines(institution_id,payslip_id,description,line_type,amount) values(p_inst,slip,'Basic salary','earning',profile.basic_salary);
   for component in select sc.amount,sc.percentage,pc.* from public.staff_pay_components sc join public.pay_components pc on pc.id=sc.pay_component_id and pc.institution_id=p_inst where sc.institution_id=p_inst and sc.staff_id=profile.staff_id and sc.is_active and pc.status='active' and sc.effective_from<=period.period_end and (sc.effective_to is null or sc.effective_to>=period.period_start) order by pc.priority loop
    if component.calculation_type='percentage' then
     if coalesce(component.percentage_basis,'basic_salary')<>'basic_salary' or component.percentage is null or component.percentage not between 0 and 100 then raise exception 'Component % needs a valid basic-salary percentage',component.name; end if;
     amount:=round(profile.basic_salary*component.percentage/100,2);
    elsif component.calculation_type in('fixed','manual') then amount:=component.amount;
    else raise exception 'Formula component % needs an approved calculation engine; use a verified manual amount',component.name; end if;
    if amount is null or amount<0 then raise exception 'Component % needs a non-negative amount',component.name; end if;
    insert into public.payslip_lines(institution_id,payslip_id,pay_component_id,description,line_type,amount) values(p_inst,slip,component.id,component.name,component.component_type,amount);
    if component.component_type='earning' then gross:=gross+amount; elsif component.component_type='deduction' then deductions:=deductions+amount; else employer:=employer+amount; end if;
   end loop;
   if deductions>gross then raise exception 'Deductions exceed gross pay for staff %',profile.staff_id; end if;
   update public.payslips set gross_pay=gross,total_deductions=deductions,net_pay=gross-deductions,employer_contributions=employer,status='calculated' where id=slip;
  end loop;
  if totalcount=0 then raise exception 'No active payroll profiles cover this period'; end if;
  update public.payroll_runs set total_gross=(select sum(gross_pay) from public.payslips where payroll_run_id=p_run),total_deductions=(select sum(total_deductions) from public.payslips where payroll_run_id=p_run),total_net=(select sum(net_pay) from public.payslips where payroll_run_id=p_run),processed_by=auth.uid(),processed_at=now() where id=p_run;
  update public.payroll_periods set status='review' where id=period.id;
 elsif p_action='approved' then
  if run.status<>'completed' or run.created_by=auth.uid() or run.processed_by=auth.uid() then raise exception 'Payroll requires an independent approver'; end if;
  update public.payslips set status='approved' where payroll_run_id=p_run;
  update public.payroll_periods set status='approved',approved_by=auth.uid(),approved_at=now() where id=period.id;
 elsif p_action='cancelled' then
  if run.status not in('draft','completed') then raise exception 'Only unapproved payroll can be cancelled'; end if;
  update public.payslips set status='cancelled' where payroll_run_id=p_run;
  update public.payroll_periods set status='draft' where id=period.id;
 else raise exception 'Invalid payroll transition'; end if;
end $$;

create or replace function public.unimis_payroll_payment152(p_inst uuid,p_run uuid,p_reference text,p_expense_account uuid,p_bank_account uuid,p_liability_account uuid)
returns void language plpgsql security definer set search_path='' as $$
declare run public.payroll_runs%rowtype; j uuid:=gen_random_uuid(); e uuid:=gen_random_uuid(); employer numeric; liability numeric; seq bigint;
begin
 if not exists(select 1 from public.unimis_effective_memberships116 m join public.roles r on r.id=m.role_id and (r.institution_id=m.institution_id or r.institution_id is null) where m.user_id=auth.uid() and m.institution_id=p_inst and m.status='active' and r.is_active and r.code in('owner','finance_officer')) then raise exception 'Finance or Owner must record a payroll payment'; end if;
 if length(trim(coalesce(p_reference,'')))<5 then raise exception 'Bank/payment reference required'; end if;
 select * into run from public.payroll_runs where id=p_run and institution_id=p_inst for update;
 if run.id is null or run.status<>'approved' or run.journal_id152 is not null then raise exception 'Only an approved, unpaid payroll can be posted'; end if;
 if run.created_by=auth.uid() or run.processed_by=auth.uid() then raise exception 'Payroll payment must be recorded by someone other than the preparer'; end if;
 if not exists(select 1 from public.finance_accounts where id=p_expense_account and institution_id=p_inst and status='active' and account_type='expense') or not exists(select 1 from public.finance_accounts where id=p_bank_account and institution_id=p_inst and status='active' and account_type='asset') or not exists(select 1 from public.finance_accounts where id=p_liability_account and institution_id=p_inst and status='active' and account_type='liability') then raise exception 'Choose valid salary expense, bank/cash asset and deduction liability accounts'; end if;
 select coalesce(sum(employer_contributions),0) into employer from public.payslips where payroll_run_id=p_run;
 liability:=run.total_deductions+employer;
 if run.total_net<=0 then raise exception 'Net payroll must be positive before payment posting'; end if;
 insert into public.finance_journal_sequences(institution_id,last_number) values(p_inst,1) on conflict(institution_id) do update set last_number=public.finance_journal_sequences.last_number+1 returning last_number into seq;
 insert into public.finance_journals(id,institution_id,journal_number,journal_date,reference,description,status,created_by,posted_at,source_type,source_id) values(j,p_inst,'JV-'||to_char(current_date,'YYYY')||'-'||lpad(seq::text,6,'0'),current_date,p_reference,'Payroll '||run.run_number,'posted',auth.uid(),now(),'payroll',p_run);
 insert into public.finance_journal_lines(institution_id,journal_id,account_id,description,debit,credit) values(p_inst,j,p_expense_account,'Salary and employer contributions',run.total_gross+employer,0),(p_inst,j,p_bank_account,'Net salaries paid',0,run.total_net);
 if liability>0 then insert into public.finance_journal_lines(institution_id,journal_id,account_id,description,debit,credit) values(p_inst,j,p_liability_account,'Deductions and employer contributions payable',0,liability); end if;
 insert into public.finance_expenses(id,institution_id,description,amount,currency_code,payment_method,payee,reference,created_by) values(e,p_inst,'Net salary payment '||run.run_number,run.total_net,'GHS','bank_transfer','Staff payroll',p_reference,auth.uid());
 update public.payroll_runs set status='posted',journal_id152=j,expense_id152=e where id=p_run;
 update public.payslips set status='paid',payment_reference=p_reference where payroll_run_id=p_run;
 update public.payroll_periods set status='paid' where id=run.payroll_period_id;
 insert into public.unimis_operations_events152(institution_id,actor_id,entity,record_id,action,note) values(p_inst,auth.uid(),'pay_runs',p_run,'posted',p_reference);
end $$;

create or replace function public.unimis_employee_payslip152(p_inst uuid,p_slip uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare slip public.payslips%rowtype;
begin
 select * into slip from public.payslips where id=p_slip and institution_id=p_inst;
 if slip.id is null then raise exception 'Payslip not found'; end if;
 if not public.unimis_operations_allowed152(p_inst,'payroll',false) and not exists(select 1 from public.staff where id=slip.staff_id and institution_id=p_inst and user_id=auth.uid() and public.unimis_employee_allowed152(p_inst) and slip.status in('approved','paid')) then raise exception 'Not authorised'; end if;
 return jsonb_build_object('slip',to_jsonb(slip),'lines',(select coalesce(jsonb_agg(to_jsonb(t)),'[]') from public.payslip_lines t where payslip_id=p_slip and institution_id=p_inst),'staff',(select jsonb_build_object('name',concat_ws(' ',first_name,last_name),'number',staff_number) from public.staff where id=slip.staff_id),'school',(select name from public.institutions where id=p_inst),'period',(select name from public.payroll_periods where id=(select payroll_period_id from public.payroll_runs where id=slip.payroll_run_id)));
end $$;

-- RPC-only mutations. Existing school-facing records remain readable under their existing RLS policies.
do $$declare x text; f record; begin
 for x in select distinct value->>'table' from jsonb_each(public.unimis_operations_config152()) loop execute format('revoke insert,update,delete on public.%I from authenticated,anon',x); end loop;
 for x in select tablename from pg_catalog.pg_tables where schemaname='public' and tablename like 'unimis_%152' loop execute format('alter table public.%I enable row level security',x); execute format('revoke all on public.%I from authenticated,anon',x); end loop;
 for f in select p.oid::regprocedure sig from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'unimis_%152' loop execute format('revoke all on function %s from public,anon',f.sig); if f.sig::text not like '%config152%' and f.sig::text not like '%payroll_transition152%' then execute format('grant execute on function %s to authenticated',f.sig); end if; end loop;
end $$;
commit;
