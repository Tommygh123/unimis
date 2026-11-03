-- 010j: strengthen performance check-ins with explicit actual-result and evidence capture.
-- Existing check-ins remain valid; new fields are nullable for backward compatibility.
alter table public.hr_performance_checkins
  add column if not exists actual_progress text,
  add column if not exists evidence text;

comment on column public.hr_performance_checkins.actual_progress is
  'Narrative of actual results/progress achieved against the agreed performance baseline at this check-in.';
comment on column public.hr_performance_checkins.evidence is
  'Evidence supporting the check-in, e.g. reports, records, links, observations, feedback or document references.';
