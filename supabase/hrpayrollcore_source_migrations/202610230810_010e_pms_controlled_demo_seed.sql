-- 010e Controlled PMS demo seed
-- Reuses the existing 2026 cycle and employee records. Safe to rerun.
-- Test stages: Esi=active/check-ins, Ama=assessment, Kwame=completed/PIP.

do $$
declare
  v_tenant uuid; v_cycle uuid; v_esi uuid; v_ama uuid; v_kwame uuid;
  r_esi uuid; r_ama uuid; r_kwame uuid;
  m record;
begin
  select id into v_tenant from public.tenants where code='TECHCITY' limit 1;
  if v_tenant is null then raise notice '010e seed skipped: tenant TECHCITY not found'; return; end if;

  select id into v_cycle from public.hr_performance_cycles
   where tenant_id=v_tenant and name='2026 Annual Performance Review' order by created_at desc limit 1;
  if v_cycle is null then
    insert into public.hr_performance_cycles(tenant_id,name,cycle_type,start_date,end_date,status)
    values(v_tenant,'2026 Annual Performance Review','annual','2026-01-01','2026-12-31','open') returning id into v_cycle;
  else
    update public.hr_performance_cycles set status='open' where id=v_cycle;
  end if;

  select id into v_esi from public.hr_employees where tenant_id=v_tenant and employee_no='EMP003' limit 1;
  select id into v_ama from public.hr_employees where tenant_id=v_tenant and employee_no='EMP001' limit 1;
  select id into v_kwame from public.hr_employees where tenant_id=v_tenant and employee_no='EMP002' limit 1;
  if v_esi is null or v_ama is null or v_kwame is null then
    raise exception '010e seed requires EMP001 Ama, EMP002 Kwame and EMP003 Esi';
  end if;

  insert into public.hr_performance_reviews(tenant_id,cycle_id,employee_id,status,plan_status,plan_activated_at)
  values(v_tenant,v_cycle,v_esi,'draft','activated',now())
  on conflict(tenant_id,cycle_id,employee_id) do update set plan_status='activated',plan_activated_at=coalesce(hr_performance_reviews.plan_activated_at,now())
  returning id into r_esi;

  insert into public.hr_performance_reviews(tenant_id,cycle_id,employee_id,status,plan_status,plan_activated_at,self_assessment_at,supervisor_assessment_at)
  values(v_tenant,v_cycle,v_ama,'reviewed','activated',now(),now(),now())
  on conflict(tenant_id,cycle_id,employee_id) do update set status='reviewed',plan_status='activated',plan_activated_at=coalesce(hr_performance_reviews.plan_activated_at,now()),self_assessment_at=now(),supervisor_assessment_at=now()
  returning id into r_ama;

  insert into public.hr_performance_reviews(tenant_id,cycle_id,employee_id,status,plan_status,plan_activated_at,self_assessment_at,supervisor_assessment_at,completed_at,strengths,skill_gaps,recommended_action)
  values(v_tenant,v_cycle,v_kwame,'completed','closed',now(),now(),now(),now(),'Professional conduct, reliability and collaboration.','Target execution and work planning need improvement.','Targeted training, mentoring and a Performance Improvement Plan.')
  on conflict(tenant_id,cycle_id,employee_id) do update set status='completed',plan_status='closed',plan_activated_at=coalesce(hr_performance_reviews.plan_activated_at,now()),self_assessment_at=now(),supervisor_assessment_at=now(),completed_at=now(),strengths=excluded.strengths,skill_gaps=excluded.skill_gaps,recommended_action=excluded.recommended_action
  returning id into r_kwame;

  -- Controlled rerun: replace only demo plan/check-in/decision/PIP content for these three 2026 reviews.
  delete from public.hr_performance_checkins where tenant_id=v_tenant and review_id in (r_esi,r_ama,r_kwame);
  delete from public.hr_performance_decisions where tenant_id=v_tenant and review_id in (r_esi,r_ama,r_kwame);
  delete from public.hr_performance_improvement_plans where tenant_id=v_tenant and review_id in (r_esi,r_ama,r_kwame);
  delete from public.hr_performance_plan_items where tenant_id=v_tenant and review_id in (r_esi,r_ama,r_kwame);

  -- ESI: active baseline + check-ins; 2 target, 2 quality, 3 conduct = 100%.
  insert into public.hr_performance_plan_items(tenant_id,review_id,metric_id,pillar,title,description,unit,direction,target_value,actual_value,weight,due_date,status)
  select v_tenant,r_esi,id,pillar,name,description,unit,direction,
    case code when 'GEN-OUTPUT' then 90 when 'GEN-DEADLINE' then 90 when 'GEN-QUALITY' then 90 when 'GEN-SOP' then 90 when 'GEN-ATTEND' then 95 else 4 end,
    case code when 'GEN-OUTPUT' then 72 when 'GEN-DEADLINE' then 78 when 'GEN-QUALITY' then 84 when 'GEN-SOP' then 88 when 'GEN-ATTEND' then 96 when 'GEN-TEAM' then 4 else 4 end,
    case code when 'GEN-OUTPUT' then 20 when 'GEN-DEADLINE' then 20 when 'GEN-QUALITY' then 15 when 'GEN-SOP' then 15 when 'GEN-ATTEND' then 10 when 'GEN-TEAM' then 10 else 10 end,
    '2026-12-31',
    case when code in ('GEN-OUTPUT','GEN-DEADLINE') then 'on_track' else 'planned' end
  from public.hr_performance_metric_library where tenant_id=v_tenant and code in ('GEN-OUTPUT','GEN-DEADLINE','GEN-QUALITY','GEN-SOP','GEN-ATTEND','GEN-TEAM','GEN-CONDUCT');

  insert into public.hr_performance_checkins(tenant_id,review_id,checkin_date,progress_percent,status,achievements,blockers,support_required,next_actions,manager_comments) values
   (v_tenant,r_esi,'2026-04-30',32,'on_track','Core assignments delivered; attendance and teamwork strong.','Some delays obtaining source documents.','Earlier access to operational records.','Complete outstanding Q2 deliverables and document evidence.','Good start; maintain evidence for each target.'),
   (v_tenant,r_esi,'2026-07-31',58,'on_track','Quality improved and most deadlines met.','Competing operational priorities.','Priority clarification during peak periods.','Focus on target completion and reduce rework.','Progress is satisfactory with clear improvement.'),
   (v_tenant,r_esi,'2026-10-15',78,'on_track','Strong attendance, collaboration and SOP compliance.','Two deliverables remain behind schedule.','Weekly supervisor check-in until year end.','Close remaining deliverables before final appraisal.','On track overall; deadline discipline remains the key focus.');

  -- AMA: assessment-stage example with deliberate self/supervisor gap.
  insert into public.hr_performance_plan_items(tenant_id,review_id,metric_id,pillar,title,description,unit,direction,target_value,actual_value,weight,due_date,status,employee_score,supervisor_score,final_score,self_comments,supervisor_comments)
  select v_tenant,r_ama,id,pillar,name,description,unit,direction,
    case code when 'GEN-OUTPUT' then 90 when 'GEN-DEADLINE' then 90 when 'GEN-QUALITY' then 90 when 'GEN-SOP' then 90 when 'GEN-ATTEND' then 95 else 4 end,
    case code when 'GEN-OUTPUT' then 88 when 'GEN-DEADLINE' then 86 when 'GEN-QUALITY' then 90 when 'GEN-SOP' then 91 when 'GEN-ATTEND' then 97 when 'GEN-TEAM' then 4 else 4 end,
    case code when 'GEN-OUTPUT' then 20 when 'GEN-DEADLINE' then 20 when 'GEN-QUALITY' then 15 when 'GEN-SOP' then 15 when 'GEN-ATTEND' then 10 when 'GEN-TEAM' then 10 else 10 end,
    '2026-12-31','on_track',
    case code when 'GEN-OUTPUT' then 94 when 'GEN-DEADLINE' then 90 when 'GEN-QUALITY' then 93 when 'GEN-SOP' then 92 when 'GEN-ATTEND' then 96 when 'GEN-TEAM' then 92 else 95 end,
    case code when 'GEN-OUTPUT' then 84 when 'GEN-DEADLINE' then 82 when 'GEN-QUALITY' then 86 when 'GEN-SOP' then 85 when 'GEN-ATTEND' then 95 when 'GEN-TEAM' then 88 else 90 end,
    case code when 'GEN-OUTPUT' then 84 when 'GEN-DEADLINE' then 82 when 'GEN-QUALITY' then 86 when 'GEN-SOP' then 85 when 'GEN-ATTEND' then 95 when 'GEN-TEAM' then 88 else 90 end,
    'Employee self-assessment: strong delivery and professional contribution during the cycle.',
    'Supervisor assessment: strong overall performance; target evidence supports a slightly lower rating than the self-assessment.'
  from public.hr_performance_metric_library where tenant_id=v_tenant and code in ('GEN-OUTPUT','GEN-DEADLINE','GEN-QUALITY','GEN-SOP','GEN-ATTEND','GEN-TEAM','GEN-CONDUCT');

  perform public.hr_performance_recalculate(v_tenant,r_ama);

  -- KWAME: completed example: high professionalism but weaker output => development/PIP path.
  insert into public.hr_performance_plan_items(tenant_id,review_id,metric_id,pillar,title,description,unit,direction,target_value,actual_value,weight,due_date,status,employee_score,supervisor_score,final_score,self_comments,supervisor_comments)
  select v_tenant,r_kwame,id,pillar,name,description,unit,direction,
    case code when 'GEN-OUTPUT' then 90 when 'GEN-DEADLINE' then 90 when 'GEN-QUALITY' then 90 when 'GEN-SOP' then 90 when 'GEN-ATTEND' then 95 else 4 end,
    case code when 'GEN-OUTPUT' then 58 when 'GEN-DEADLINE' then 62 when 'GEN-QUALITY' then 74 when 'GEN-SOP' then 78 when 'GEN-ATTEND' then 97 when 'GEN-TEAM' then 4 else 4 end,
    case code when 'GEN-OUTPUT' then 20 when 'GEN-DEADLINE' then 20 when 'GEN-QUALITY' then 15 when 'GEN-SOP' then 15 when 'GEN-ATTEND' then 10 when 'GEN-TEAM' then 10 else 10 end,
    '2026-12-31',case when code in ('GEN-OUTPUT','GEN-DEADLINE') then 'at_risk' else 'on_track' end,
    case code when 'GEN-OUTPUT' then 70 when 'GEN-DEADLINE' then 68 when 'GEN-QUALITY' then 78 when 'GEN-SOP' then 80 when 'GEN-ATTEND' then 96 when 'GEN-TEAM' then 90 else 92 end,
    case code when 'GEN-OUTPUT' then 58 when 'GEN-DEADLINE' then 62 when 'GEN-QUALITY' then 74 when 'GEN-SOP' then 78 when 'GEN-ATTEND' then 96 when 'GEN-TEAM' then 90 else 92 end,
    case code when 'GEN-OUTPUT' then 58 when 'GEN-DEADLINE' then 62 when 'GEN-QUALITY' then 74 when 'GEN-SOP' then 78 when 'GEN-ATTEND' then 96 when 'GEN-TEAM' then 90 else 92 end,
    'Employee acknowledges target-delivery challenges but reports strong teamwork and reliability.',
    'Supervisor confirms good conduct but identifies a material output and planning gap requiring structured support.'
  from public.hr_performance_metric_library where tenant_id=v_tenant and code in ('GEN-OUTPUT','GEN-DEADLINE','GEN-QUALITY','GEN-SOP','GEN-ATTEND','GEN-TEAM','GEN-CONDUCT');

  perform public.hr_performance_recalculate(v_tenant,r_kwame);
  update public.hr_performance_reviews set status='completed',plan_status='closed',completed_at=now(),strengths='Professional conduct, attendance and collaboration.',skill_gaps='Target execution, prioritisation and deadline management.',recommended_action='Training + mentoring + monitored Performance Improvement Plan.' where id=r_kwame;

  insert into public.hr_performance_decisions(tenant_id,review_id,action_type,rationale,status) values
   (v_tenant,r_kwame,'training','Target output is below expectation while professional conduct remains strong; targeted skills development is appropriate.','approved'),
   (v_tenant,r_kwame,'mentoring','Provide structured work-planning and prioritisation support.','approved'),
   (v_tenant,r_kwame,'pip','Use measurable improvement targets and scheduled supervisor reviews.','approved');

  insert into public.hr_performance_improvement_plans(tenant_id,employee_id,review_id,title,objectives,actions_support,start_date,review_date,status)
  values(v_tenant,v_kwame,r_kwame,'2026 Target Delivery Improvement Plan','Improve target completion and deadline delivery to at least 80% while maintaining current professional conduct.','Weekly planning review with supervisor; prioritisation coaching; targeted training; monthly evidence-based progress review.','2026-10-23','2026-12-23','open');

  raise notice '010e PMS demo seed complete: Esi active/check-ins, Ama assessed, Kwame completed/PIP.';
end $$;
