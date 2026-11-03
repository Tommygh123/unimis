-- 010p PMS E2E test seed/reset
-- Purpose: preserve existing staged PMS demo records while reserving EMP004 (Kojo Owusu)
-- as a clean employee for a true UI-driven end-to-end PMS test.
-- No appraisal is pre-created for EMP004: the tester must create it through the UI.
do $$
declare
  v_tenant uuid;
  v_employee uuid;
  v_cycle uuid;
  v_review uuid;
  n integer;
begin
  select e.tenant_id into v_tenant
  from public.hr_employees e
  where e.employee_no in ('EMP001','EMP002','EMP003','EMP004')
  group by e.tenant_id
  having count(distinct e.employee_no)=4
  order by e.tenant_id
  limit 1;
  if v_tenant is null then
    raise exception '010p: expected EMP001-EMP004 under one demo tenant. Run the earlier demo seed migrations first.';
  end if;

  select id into v_employee from public.hr_employees
  where tenant_id=v_tenant and employee_no='EMP004' limit 1;
  if v_employee is null then raise exception '010p: EMP004 not found'; end if;

  -- Ensure the controlled 2026 test cycle exists and remains open.
  select id into v_cycle from public.hr_performance_cycles
  where tenant_id=v_tenant and name='2026 Annual Performance Review'
  order by created_at desc limit 1;
  if v_cycle is null then
    insert into public.hr_performance_cycles(tenant_id,name,cycle_type,start_date,end_date,status)
    values(v_tenant,'2026 Annual Performance Review','annual','2026-01-01','2026-12-31','open')
    returning id into v_cycle;
  else
    update public.hr_performance_cycles
    set start_date='2026-01-01',end_date='2026-12-31',status='open'
    where id=v_cycle;
  end if;

  -- Guarantee the standard editable KPI library needed for the E2E test.
  insert into public.hr_performance_metric_library
    (tenant_id,code,name,pillar,industry,unit,direction,description,default_target,default_weight,active)
  values
    (v_tenant,'GEN-OUTPUT','Target / Output Achievement','target_output','general','percent','higher_better','Achievement against agreed quantitative targets, deliverables or milestones.',90,20,true),
    (v_tenant,'GEN-DEADLINE','Deadline Delivery','target_output','general','percent','higher_better','Delivery of agreed work within committed timelines.',90,20,true),
    (v_tenant,'GEN-QUALITY','Work Quality & Accuracy','responsibility_quality','general','percent','higher_better','Accuracy, completeness, rework and quality of assigned responsibilities.',90,15,true),
    (v_tenant,'GEN-SOP','Responsibility / SOP Execution','responsibility_quality','general','percent','higher_better','Execution of job-description duties, procedures and controls.',90,15,true),
    (v_tenant,'GEN-ATTEND','Attendance & Punctuality','professional_conduct','general','percent','higher_better','Attendance and punctuality considered with authorised context.',95,10,true),
    (v_tenant,'GEN-TEAM','Collaboration & Communication','professional_conduct','general','score','higher_better','Teamwork, communication and constructive workplace behaviour.',4,10,true),
    (v_tenant,'GEN-CONDUCT','Professional Conduct & Ethics','professional_conduct','general','score','higher_better','Integrity, professionalism and adherence to organisational values.',4,10,true)
  on conflict(tenant_id,code) do update set
    name=excluded.name,pillar=excluded.pillar,industry=excluded.industry,unit=excluded.unit,
    direction=excluded.direction,description=excluded.description,default_target=excluded.default_target,
    default_weight=excluded.default_weight,active=true;

  -- Clean only EMP004's appraisal in this cycle so the entire workflow is tested from the UI.
  select id into v_review from public.hr_performance_reviews
  where tenant_id=v_tenant and employee_id=v_employee and cycle_id=v_cycle limit 1;
  if v_review is not null then
    -- Unlock only this disposable E2E record before removing it.
    update public.hr_performance_reviews
    set finalization_status='not_started',finalized_at=null,finalized_by=null,
        final_score=null,final_rating=null,completed_at=null,status='draft',plan_status='planning'
    where id=v_review;
    delete from public.hr_performance_improvement_plans where tenant_id=v_tenant and review_id=v_review;
    delete from public.hr_performance_reviews where tenant_id=v_tenant and id=v_review;
  end if;

  select count(*) into n from public.hr_performance_metric_library
  where tenant_id=v_tenant and code in ('GEN-OUTPUT','GEN-DEADLINE','GEN-QUALITY','GEN-SOP','GEN-ATTEND','GEN-TEAM','GEN-CONDUCT') and active;
  if n<>7 then raise exception '010p verification failed: expected 7 active generic PMS measures, got %',n; end if;
  if exists(select 1 from public.hr_performance_reviews where tenant_id=v_tenant and employee_id=v_employee and cycle_id=v_cycle) then
    raise exception '010p verification failed: EMP004 must start without a review';
  end if;
  raise notice '010p ready: EMP004 Kojo Owusu is clean for UI-driven PMS E2E testing; 2026 cycle open; 7 standard KPIs active.';
end $$;
