-- 014 Performance Setup restructure
alter table public.hr_performance_templates add column if not exists department_id uuid references public.departments(id) on delete set null;
alter table public.hr_performance_templates add column if not exists position_id uuid references public.hr_positions(id) on delete set null;
alter table public.hr_performance_templates add column if not exists grade_id uuid references public.hr_job_grades(id) on delete set null;
alter table public.hr_performance_template_items add column if not exists metric_id uuid references public.hr_performance_metric_library(id) on delete set null;
create unique index if not exists uq_perf_template_metric on public.hr_performance_template_items(template_id,metric_id) where metric_id is not null;
create index if not exists idx_perf_templates_assignment on public.hr_performance_templates(tenant_id,industry,department_id,position_id,grade_id,active);
