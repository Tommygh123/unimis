-- 015 AI-assisted Performance Data Hub
alter table public.hr_performance_metric_library add column if not exists aggregation_method text not null default 'sum'
 check (aggregation_method in ('sum','average','count','latest','min','max'));
alter table public.hr_performance_template_items add column if not exists aggregation_method text not null default 'sum'
 check (aggregation_method in ('sum','average','count','latest','min','max'));

create table if not exists public.hr_performance_mapping_profiles(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete cascade,
 name text not null, source_type text not null default 'csv',
 mapping_config jsonb not null default '{}'::jsonb,
 active boolean not null default true,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(tenant_id,name)
);

create table if not exists public.hr_performance_import_batches(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete cascade,
 file_name text not null, source_type text not null default 'csv',
 mapping_config jsonb not null default '{}'::jsonb,
 total_rows int not null default 0, accepted_rows int not null default 0,
 rejected_rows int not null default 0, duplicate_rows int not null default 0,
 status text not null default 'uploaded', error_summary jsonb not null default '[]'::jsonb,
 created_at timestamptz not null default now(), completed_at timestamptz
);

create table if not exists public.hr_performance_source_records(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete cascade,
 batch_id uuid references public.hr_performance_import_batches(id) on delete set null,
 row_number int, employee_ref text not null, employee_name text,
 observed_at date not null, period_key text not null,
 metric_id uuid references public.hr_performance_metric_library(id) on delete set null,
 metric_code text not null, metric_name text not null,
 raw_column text, raw_value text, numeric_value numeric(18,4), unit text,
 aggregation_method text not null default 'sum',
 verification_status text not null default 'import_validated',
 source_record_key text not null, created_at timestamptz not null default now(),
 unique(tenant_id,source_record_key)
);

do $$ declare t text; begin
 foreach t in array array['hr_performance_mapping_profiles','hr_performance_import_batches','hr_performance_source_records'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('drop policy if exists tenant_member_all on public.%I',t);
  execute format('create policy tenant_member_all on public.%I for all using (public.is_tenant_member(tenant_id)) with check (public.is_tenant_member(tenant_id))',t);
 end loop;
end $$;

create index if not exists idx_perf_source_employee_period on public.hr_performance_source_records(tenant_id,employee_ref,period_key,metric_code);
create index if not exists idx_perf_import_batches_created on public.hr_performance_import_batches(tenant_id,created_at desc);

-- Aggregate validated source observations into the existing Performance Ledger.
create or replace function public.hr_aggregate_performance_source_records(p_tenant uuid,p_period text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r record; n int:=0; v numeric;
begin
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 for r in
  select employee_ref,max(coalesce(employee_name,employee_ref)) employee_name,metric_code,max(metric_name) metric_name,
         max(metric_id::text)::uuid metric_id,max(unit) unit,max(aggregation_method) aggregation_method,
         min(observed_at) first_date,max(observed_at) last_date
  from hr_performance_source_records
  where tenant_id=p_tenant and period_key=p_period and verification_status='import_validated'
  group by employee_ref,metric_code
 loop
  select case r.aggregation_method
    when 'average' then avg(numeric_value)
    when 'count' then count(numeric_value)::numeric
    when 'latest' then (array_agg(numeric_value order by observed_at desc,id desc))[1]
    when 'min' then min(numeric_value)
    when 'max' then max(numeric_value)
    else sum(numeric_value) end into v
  from hr_performance_source_records
  where tenant_id=p_tenant and period_key=p_period and employee_ref=r.employee_ref and metric_code=r.metric_code and verification_status='import_validated';

  insert into hr_performance_ledger(tenant_id,employee_ref,employee_name,period_key,fact_code,fact_name,measurement_class,actual_value,target_value,unit,direction,source_code,verification_status,evidence_note,observed_at)
  select p_tenant,r.employee_ref,r.employee_name,p_period,r.metric_code,r.metric_name,
         coalesce(m.measurement_class,'kpi'),v,m.default_target,r.unit,coalesce(m.direction,'higher_better'),
         'CSV-DATA-HUB','system_verified',
         'Aggregated from validated Performance Source Records using '||upper(r.aggregation_method)||'.',r.last_date
  from hr_performance_metric_library m where m.id=r.metric_id
  on conflict(tenant_id,employee_ref,period_key,fact_code) do update
   set actual_value=excluded.actual_value,verification_status=excluded.verification_status,evidence_note=excluded.evidence_note,observed_at=excluded.observed_at;
  n:=n+1;
 end loop;
 return jsonb_build_object('period',p_period,'ledger_facts',n);
end $$;
grant execute on function public.hr_aggregate_performance_source_records(uuid,text) to authenticated;
