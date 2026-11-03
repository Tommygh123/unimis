-- 013 Performance Automation Engine
-- Universal evidence model: KPI + Task/SLA + Work Standard + Compliance + Competency + Attendance.

alter table public.hr_performance_metric_library add column if not exists measurement_class text not null default 'kpi';
alter table public.hr_performance_metric_library add column if not exists measurement_frequency text not null default 'monthly';
alter table public.hr_performance_metric_library add column if not exists source_type text not null default 'verified_evidence';
alter table public.hr_performance_metric_library add column if not exists verification_rule text not null default 'supervisor_review';
alter table public.hr_performance_metric_library add column if not exists formula_expression text;

create table if not exists public.hr_performance_templates(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 code text not null, name text not null, industry text not null default 'general', department_name text,
 position_title text not null, grade_name text, description text, active boolean not null default true,
 created_at timestamptz not null default now(), unique(tenant_id,code)
);
create table if not exists public.hr_performance_template_items(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 template_id uuid not null references public.hr_performance_templates(id) on delete cascade,
 code text not null, name text not null, measurement_class text not null,
 target_value numeric(14,2), unit text not null default 'percent', direction text not null default 'higher_better',
 weight numeric(6,2) not null, frequency text not null default 'monthly', source_type text not null,
 verification_rule text not null default 'system_or_supervisor', formula_expression text, display_order int not null default 10,
 unique(template_id,code)
);
create table if not exists public.hr_performance_data_sources(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 code text not null, name text not null, source_type text not null, trust_level text not null default 'verified',
 status text not null default 'active', description text, last_sync_at timestamptz, created_at timestamptz not null default now(),
 unique(tenant_id,code)
);
create table if not exists public.hr_performance_ledger(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 employee_ref text not null, employee_name text not null, position_title text, grade_name text,
 period_key text not null, fact_code text not null, fact_name text not null, measurement_class text not null,
 actual_value numeric(14,2), target_value numeric(14,2), unit text, direction text not null default 'higher_better',
 source_code text not null, verification_status text not null default 'system_verified', evidence_note text,
 observed_at date not null, created_at timestamptz not null default now(), unique(tenant_id,employee_ref,period_key,fact_code)
);
create table if not exists public.hr_automated_checkins(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 employee_ref text not null, employee_name text not null, period_key text not null, period_label text not null,
 prepared_score numeric(6,2), status text not null default 'prepared', exception_count int not null default 0,
 exception_summary text, employee_response text, supervisor_response text, prepared_at timestamptz not null default now(),
 unique(tenant_id,employee_ref,period_key)
);

do $$ declare t text; begin
 foreach t in array array['hr_performance_templates','hr_performance_template_items','hr_performance_data_sources','hr_performance_ledger','hr_automated_checkins'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('drop policy if exists tenant_member_all on public.%I',t);
  execute format('create policy tenant_member_all on public.%I for all using (public.is_tenant_member(tenant_id)) with check (public.is_tenant_member(tenant_id))',t);
 end loop;
end $$;

create index if not exists idx_perf_ledger_employee_period on public.hr_performance_ledger(tenant_id,employee_ref,period_key);
create index if not exists idx_auto_checkins_period on public.hr_automated_checkins(tenant_id,period_key,status);

create or replace function public.hr_seed_bank_performance_automation(p_tenant uuid) returns jsonb language plpgsql security definer set search_path=public as $$
declare tpl uuid; r record; p text; d date; disb numeric; npl numeric; tat numeric; kyc numeric; att numeric; sc numeric; exc int;
begin
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 insert into hr_performance_templates(tenant_id,code,name,industry,department_name,position_title,grade_name,description)
 values(p_tenant,'BANK-CREDIT-G3','Grade 3 Credit Officer Performance Template','banking','Credit','Credit Officer','Grade 3','Reference template proving position/grade performance automation for Adom Rural Bank.')
 on conflict(tenant_id,code) do update set name=excluded.name,description=excluded.description returning id into tpl;
 if tpl is null then select id into tpl from hr_performance_templates where tenant_id=p_tenant and code='BANK-CREDIT-G3'; end if;
 insert into hr_performance_template_items(tenant_id,template_id,code,name,measurement_class,target_value,unit,direction,weight,frequency,source_type,verification_rule,formula_expression,display_order) values
 (p_tenant,tpl,'DISB','Loan Disbursement Volume','kpi',500000,'GHS','higher_better',25,'quarterly','import_or_api','trusted_source','actual / target * 100',10),
 (p_tenant,tpl,'NPL','NPL Ratio','kpi',3,'percent','lower_better',20,'monthly','import_or_api','trusted_source','target / actual * 100 capped at 100',20),
 (p_tenant,tpl,'TAT','Loan Turnaround Time','task_sla',48,'hours','lower_better',15,'monthly','workflow_or_import','trusted_source','target / actual * 100 capped at 100',30),
 (p_tenant,tpl,'KYC','KYC / Site Visit Accuracy','compliance',100,'percent','higher_better',15,'monthly','checklist_or_import','compliance_review','actual / target * 100',40),
 (p_tenant,tpl,'ATT','Attendance & Punctuality','attendance',95,'percent','higher_better',10,'monthly','hr_attendance','system_verified','leave-adjusted attendance',50),
 (p_tenant,tpl,'CONDUCT','Professional Conduct & Service','competency',4,'score_5','higher_better',15,'quarterly','anchored_observation','supervisor_review','anchored 1-5 rubric',60)
 on conflict(template_id,code) do update set name=excluded.name,measurement_class=excluded.measurement_class,target_value=excluded.target_value,weight=excluded.weight,source_type=excluded.source_type;
 insert into hr_performance_data_sources(tenant_id,code,name,source_type,trust_level,description) values
 (p_tenant,'HR-ATT','HRPayrollCore Attendance','native','system','Attendance and approved leave reconciliation.'),
 (p_tenant,'BANK-CSV','Core Banking CSV / Excel','import','verified','Fallback when direct API access is unavailable.'),
 (p_tenant,'BANK-API','Core Banking API','api','trusted','Future automated operational synchronization.'),
 (p_tenant,'CHECKLIST','Compliance / Work Checklist','checklist','verified','Structured compliance and work-standard observations.'),
 (p_tenant,'SUP-RUBRIC','Anchored Supervisor Observation','observation','human_verified','Behavioural judgment using observable anchors, not free-form scoring.')
 on conflict(tenant_id,code) do update set name=excluded.name,description=excluded.description;

 for r in select * from (values
  ('2026-07'::text,'2026-07-31'::date,150000::numeric,2.6::numeric,46::numeric,100::numeric,98::numeric),
  ('2026-08','2026-08-31'::date,160000,2.8,49,100,96),
  ('2026-09','2026-09-30'::date,165000,2.7,53,100,97)
 ) v(period_key,observed_date,disbursement,npl_ratio,turnaround,kyc_accuracy,attendance) loop
  p:=r.period_key; d:=r.observed_date; disb:=r.disbursement; npl:=r.npl_ratio; tat:=r.turnaround; kyc:=r.kyc_accuracy; att:=r.attendance;
  insert into hr_performance_ledger(tenant_id,employee_ref,employee_name,position_title,grade_name,period_key,fact_code,fact_name,measurement_class,actual_value,target_value,unit,direction,source_code,verification_status,evidence_note,observed_at) values
  (p_tenant,'BANK-KM-001','Kojo Mensah','Credit Officer','Grade 3',p,'DISB','Loan Disbursement Volume','kpi',disb,166666.67,'GHS','higher_better','BANK-CSV','system_verified','Imported core banking operational fact',d),
  (p_tenant,'BANK-KM-001','Kojo Mensah','Credit Officer','Grade 3',p,'NPL','NPL Ratio','kpi',npl,3,'percent','lower_better','BANK-CSV','system_verified','Portfolio quality extract',d),
  (p_tenant,'BANK-KM-001','Kojo Mensah','Credit Officer','Grade 3',p,'TAT','Loan Turnaround Time','task_sla',tat,48,'hours','lower_better','BANK-API','system_verified','Workflow turnaround measurement',d),
  (p_tenant,'BANK-KM-001','Kojo Mensah','Credit Officer','Grade 3',p,'KYC','KYC / Site Visit Accuracy','compliance',kyc,100,'percent','higher_better','CHECKLIST','verified','Compliance checklist result',d),
  (p_tenant,'BANK-KM-001','Kojo Mensah','Credit Officer','Grade 3',p,'ATT','Attendance & Punctuality','attendance',att,95,'percent','higher_better','HR-ATT','system_verified','Approved leave excluded from denominator',d)
  on conflict(tenant_id,employee_ref,period_key,fact_code) do update set actual_value=excluded.actual_value,evidence_note=excluded.evidence_note;
  sc:=round(((least(disb/166666.67,1)*25)+(least(3/npl,1)*20)+(least(48/tat,1)*15)+(least(kyc/100,1)*15)+(least(att/95,1)*10)+15)/100*100,1);
  exc:=case when tat>48 then 1 else 0 end;
  insert into hr_automated_checkins(tenant_id,employee_ref,employee_name,period_key,period_label,prepared_score,status,exception_count,exception_summary)
  values(p_tenant,'BANK-KM-001','Kojo Mensah',p,to_char(d,'FMMonth YYYY'),sc,case when exc>0 then 'exception_review' else 'prepared' end,exc,case when exc>0 then 'Loan turnaround exceeded the 48-hour SLA. Employee/supervisor context requested; all other verified facts require no re-entry.' else 'All verified measures are within expected range. Human input is optional.' end)
  on conflict(tenant_id,employee_ref,period_key) do update set prepared_score=excluded.prepared_score,status=excluded.status,exception_count=excluded.exception_count,exception_summary=excluded.exception_summary;
 end loop;
 return jsonb_build_object('template','BANK-CREDIT-G3','employee','Kojo Mensah','periods',3,'mode','deterministic simulation');
end $$;
grant execute on function public.hr_seed_bank_performance_automation(uuid) to authenticated;
