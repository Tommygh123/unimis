-- 010z: Central tenant-safe automatic code generation.
-- Existing codes are preserved. New blank/null codes are generated at INSERT time.

create table if not exists public.hr_code_counters(
  tenant_key uuid not null,
  entity_key text not null,
  last_value bigint not null default 0,
  updated_at timestamptz not null default now(),
  primary key(tenant_key,entity_key)
);

create or replace function public.hr_next_code(p_tenant uuid,p_entity text,p_prefix text,p_table regclass)
returns text language plpgsql security definer set search_path=public as $$
declare
  k uuid:=coalesce(p_tenant,'00000000-0000-0000-0000-000000000000'::uuid);
  n bigint;
  mx bigint:=0;
begin
  perform pg_advisory_xact_lock(hashtext(k::text||':'||p_entity));
  execute format('select coalesce(max((regexp_match(code, %L))[1]::bigint),0) from %s where coalesce(tenant_id,%L::uuid)=%L::uuid and code ~ %L',
    '^'||p_prefix||'-([0-9]+)$',p_table,'00000000-0000-0000-0000-000000000000',k::text,'^'||p_prefix||'-[0-9]+$') into mx;
  insert into public.hr_code_counters(tenant_key,entity_key,last_value)
  values(k,p_entity,mx)
  on conflict(tenant_key,entity_key) do update set last_value=greatest(public.hr_code_counters.last_value,excluded.last_value),updated_at=now();
  update public.hr_code_counters set last_value=last_value+1,updated_at=now()
   where tenant_key=k and entity_key=p_entity returning last_value into n;
  return p_prefix||'-'||lpad(n::text,4,'0');
end $$;

create or replace function public.hr_autocode_row()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.code is null or btrim(new.code)='' then
    new.code:=public.hr_next_code(new.tenant_id,TG_TABLE_NAME,TG_ARGV[0],TG_RELID);
  end if;
  return new;
end $$;

create or replace function public.hr_auto_employee_no()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.employee_no is null or btrim(new.employee_no)='' then
    new.employee_no:=public.hr_next_code(new.tenant_id,'hr_employees','EMP',TG_RELID);
  end if;
  return new;
end $$;

create or replace function public.hr_auto_tenant_code()
returns trigger language plpgsql security definer set search_path=public as $$
declare n bigint;
begin
  if new.code is null or btrim(new.code)='' then
    perform pg_advisory_xact_lock(hashtext('tenant:auto-code'));
    select coalesce(max((regexp_match(code,'^ORG-([0-9]+)$'))[1]::bigint),0) into n from public.tenants where code ~ '^ORG-[0-9]+$';
    new.code:='ORG-'||lpad((n+1)::text,4,'0');
  end if;
  return new;
end $$;

drop trigger if exists trg_auto_tenant_code on public.tenants;
create trigger trg_auto_tenant_code before insert on public.tenants for each row execute function public.hr_auto_tenant_code();

drop trigger if exists trg_auto_employee_no on public.hr_employees;
create trigger trg_auto_employee_no before insert on public.hr_employees for each row execute function public.hr_auto_employee_no();

do $$
declare r record;
begin
  for r in select * from (values
    ('branches','BR'),('departments','DEP'),('hr_job_grades','GRD'),('hr_positions','POS'),
    ('hr_work_schedules','SCH'),('hr_leave_types','LVE'),('hr_performance_pillars','PIL'),
    ('hr_performance_metric_library','KPI'),('hr_performance_decision_rules','PDR'),
    ('hr_attendance_sites','SITE'),('hr_training_programs','TRN'),
    ('payroll_pay_groups','PGR'),('payroll_components','PAY'),('payroll_earning_sources','PES'),
    ('payroll_deduction_definitions','PDD'),('payroll_adjustments','ADJ'),('payroll_relief_types','RLF')
  ) as x(tbl,prefix)
  loop
    if to_regclass('public.'||r.tbl) is not null then
      execute format('drop trigger if exists trg_auto_code on public.%I',r.tbl);
      execute format('create trigger trg_auto_code before insert on public.%I for each row execute function public.hr_autocode_row(%L)',r.tbl,r.prefix);
    end if;
  end loop;
end $$;

grant execute on function public.hr_next_code(uuid,text,text,regclass) to authenticated;

-- Keep manually meaningful external identifiers untouched: Ghana Card, TIN, SSNIT,
-- bank/MoMo numbers, certificate numbers and bank/payment references are not internal codes.
