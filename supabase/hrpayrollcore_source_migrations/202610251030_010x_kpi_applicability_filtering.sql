-- 010x: KPI applicability and role-aware PMS recommendations
alter table public.hr_performance_metric_library
  add column if not exists scope_level text not null default 'organization',
  add column if not exists department_id uuid references public.departments(id) on delete set null,
  add column if not exists position_id uuid references public.hr_positions(id) on delete set null;

alter table public.hr_performance_metric_library drop constraint if exists hr_performance_metric_library_scope_level_check;
alter table public.hr_performance_metric_library add constraint hr_performance_metric_library_scope_level_check
  check (scope_level in ('organization','department','position'));

create index if not exists idx_hr_perf_metric_scope on public.hr_performance_metric_library(tenant_id,scope_level,department_id,position_id) where active=true;

-- Existing general KPIs remain organization-wide. Sector-specific metrics stay available as overrides
-- unless HR explicitly scopes them to a department/position.
update public.hr_performance_metric_library
set scope_level=coalesce(scope_level,'organization')
where scope_level is null;

-- Add realistic Operations Officer KPIs for tenants that have the seeded Operations Officer position.
do $$
declare t record; d uuid; p uuid;
begin
 for t in select id from public.tenants loop
   select hp.id,hp.department_id into p,d from public.hr_positions hp
   where hp.tenant_id=t.id and lower(hp.title)='operations officer' and hp.active=true limit 1;
   if p is not null then
     insert into public.hr_performance_metric_library
       (tenant_id,code,name,pillar,industry,unit,direction,description,default_target,default_weight,scope_level,department_id,position_id,active)
     values
       (t.id,'OPS-TASK','Task Completion Rate','target_output','general','percent','higher_better','Percentage of assigned operational tasks completed to the agreed standard within the appraisal period.',90,30,'position',d,p,true),
       (t.id,'OPS-DEADLINE','Operational Deadline Compliance','target_output','general','percent','higher_better','Percentage of assigned operational deliverables completed by the agreed deadline.',90,20,'position',d,p,true),
       (t.id,'OPS-QUALITY','Operational Work Quality & Accuracy','responsibility_quality','general','percent','higher_better','Accuracy and completeness of operational work, with avoidable rework kept within agreed tolerance.',95,25,'position',d,p,true),
       (t.id,'OPS-SOP','SOP & Process Compliance','responsibility_quality','general','percent','higher_better','Compliance with approved operating procedures, controls and required documentation.',95,15,'position',d,p,true),
       (t.id,'OPS-CONDUCT','Operational Collaboration & Conduct','professional_conduct','general','score','higher_better','Collaboration, communication, accountability and professional conduct in operational work.',4,10,'position',d,p,true)
     on conflict(tenant_id,code) do update set
       name=excluded.name,pillar=excluded.pillar,industry=excluded.industry,unit=excluded.unit,direction=excluded.direction,
       description=excluded.description,default_target=excluded.default_target,default_weight=excluded.default_weight,
       scope_level=excluded.scope_level,department_id=excluded.department_id,position_id=excluded.position_id,active=true;
   end if;
 end loop;
end $$;
