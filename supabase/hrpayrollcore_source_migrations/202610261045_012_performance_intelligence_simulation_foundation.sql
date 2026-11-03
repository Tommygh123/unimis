-- 012 Performance Intelligence & multi-industry simulation foundation
create table if not exists public.hr_performance_simulation_cases (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  sector text not null,
  organization_name text not null,
  employee_name text not null,
  role_title text not null,
  scenario_code text not null,
  objective_score numeric(6,2),
  attendance_percent numeric(6,2),
  manager_rating numeric(4,2),
  evidence_completeness numeric(6,2) default 100,
  employee_reflection text,
  intelligence_summary text,
  exception_flags jsonb not null default '[]'::jsonb,
  recommended_action text,
  policy_gate text,
  created_at timestamptz not null default now(),
  unique(tenant_id,scenario_code)
);

alter table public.hr_performance_simulation_cases enable row level security;
drop policy if exists hr_performance_simulation_cases_member on public.hr_performance_simulation_cases;
create policy hr_performance_simulation_cases_member on public.hr_performance_simulation_cases
for all using (public.is_tenant_member(tenant_id)) with check (public.is_tenant_member(tenant_id));

create or replace function public.hr_seed_performance_intelligence_simulations(p_tenant uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 insert into public.hr_performance_simulation_cases
 (tenant_id,sector,organization_name,employee_name,role_title,scenario_code,objective_score,attendance_percent,manager_rating,evidence_completeness,employee_reflection,intelligence_summary,exception_flags,recommended_action,policy_gate)
 values
 (p_tenant,'Trading','Aseda Trading Ltd','Adwoa Mensah','Sales Officer','TRADING-HIGH',96.4,97,4.6,100,'Exceeded my sales and collection targets and supported two new accounts.','Strong objective performance with complete evidence. Manager rating is aligned with operational results.','[]','Recognize performance; consider stretch targets and succession readiness.','Eligible subject to time-in-grade and approved vacancy.'),
 (p_tenant,'Trading','Aseda Trading Ltd','Kwame Boateng','Storekeeper','TRADING-BIAS',91.2,96,2.4,100,'Stock counts improved and variances reduced during the period.','Objective evidence is strong but the manager rating is materially lower. Calibration review is recommended before finalization.','["manager_objective_mismatch"]','Route to HR calibration; do not auto-adjust the rating.','Decision held pending calibration.'),
 (p_tenant,'Education','Apex Technical College','Efua Owusu','Lecturer','EDU-BALANCED',88.5,94,4.1,95,'Completed teaching plan and practical assessments; requested support for digital content.','Good teaching delivery with a minor attendance gap and a clear development request.','["attendance_below_target"]','Coaching plus digital-learning development plan.','No adverse decision; development action recommended.'),
 (p_tenant,'NGO','HopeBridge Foundation','Yaw Asare','Project Officer','NGO-EVIDENCE',92.0,98,4.3,62,'Field milestones were completed but several beneficiary reports are still being uploaded.','Reported outcomes are strong, but evidence completeness is insufficient for a high-confidence final assessment.','["evidence_gap"]','Request missing field evidence before assessment finalization.','Final score remains provisional until evidence threshold is met.'),
 (p_tenant,'Healthcare','Akwaaba Community Hospital','Akosua Frimpong','Records Officer','HEALTH-QUALITY',84.0,99,4.0,100,'Improved records turnaround but documentation errors remain a concern.','Attendance and conduct are strong; quality indicators show a recurring documentation issue.','["quality_risk"]','Targeted records-quality coaching and 60-day follow-up.','No PIP unless quality remains below policy threshold.'),
 (p_tenant,'Manufacturing','Prime Manufacturing Ltd','Kofi Antwi','Maintenance Technician','MFG-PIP',67.5,88,2.8,100,'Downtime response improved late in the period after additional coaching.','Multiple objective indicators remain below threshold despite complete evidence. Improvement is visible but not yet sustained.','["performance_below_threshold","attendance_risk"]','Supervisor review for structured PIP with measurable 60-day milestones.','PIP eligible; disciplinary action is not automatic.'),
 (p_tenant,'Hospitality','Akwaba Hotel','Mabel Addo','Front Desk Officer','HOTEL-PROMO-GATE',95.0,98,4.7,100,'Guest feedback and reservation accuracy were strong throughout the period.','High performance and strong service evidence. Promotion readiness is positive, but policy eligibility must still be checked.','["promotion_policy_gate"]','Place in talent pool; check time-in-grade before promotion approval.','Not yet eligible: minimum time-in-grade not satisfied.')
 on conflict (tenant_id,scenario_code) do update set
 objective_score=excluded.objective_score,attendance_percent=excluded.attendance_percent,manager_rating=excluded.manager_rating,evidence_completeness=excluded.evidence_completeness,
 employee_reflection=excluded.employee_reflection,intelligence_summary=excluded.intelligence_summary,exception_flags=excluded.exception_flags,recommended_action=excluded.recommended_action,policy_gate=excluded.policy_gate;
 return jsonb_build_object('ok',true,'cases',7);
end $$;

grant execute on function public.hr_seed_performance_intelligence_simulations(uuid) to authenticated;
