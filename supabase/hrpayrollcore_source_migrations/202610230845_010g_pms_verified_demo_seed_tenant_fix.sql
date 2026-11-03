-- 010g PMS verified controlled demo seed fix (corrected for migration execution context)
-- Guarantees the generic metric library exists, reuses one 2026 cycle, seeds three staged reviews,
-- and aborts the migration if the expected demo state is not present.
do $$
declare
 v_tenant uuid; v_cycle uuid; v_esi uuid; v_ama uuid; v_kwame uuid;
 r_esi uuid; r_ama uuid; r_kwame uuid; n int; w numeric;
begin
 select e.tenant_id into v_tenant
 from public.hr_employees e
 where e.employee_no in ('EMP001','EMP002','EMP003')
 group by e.tenant_id
 having count(distinct e.employee_no)=3
 order by e.tenant_id
 limit 1;
 if v_tenant is null then raise exception '010g: could not find EMP001, EMP002 and EMP003 under one tenant'; end if;
 select id into v_esi from public.hr_employees where tenant_id=v_tenant and employee_no='EMP003' limit 1;
 select id into v_ama from public.hr_employees where tenant_id=v_tenant and employee_no='EMP001' limit 1;
 select id into v_kwame from public.hr_employees where tenant_id=v_tenant and employee_no='EMP002' limit 1;
 if v_esi is null or v_ama is null or v_kwame is null then raise exception '010g requires EMP001, EMP002 and EMP003'; end if;

 select id into v_cycle from public.hr_performance_cycles where tenant_id=v_tenant and name='2026 Annual Performance Review' order by created_at desc limit 1;
 if v_cycle is null then
  insert into public.hr_performance_cycles(tenant_id,name,cycle_type,start_date,end_date,status)
  values(v_tenant,'2026 Annual Performance Review','annual','2026-01-01','2026-12-31','open') returning id into v_cycle;
 else update public.hr_performance_cycles set status='open',start_date='2026-01-01',end_date='2026-12-31' where id=v_cycle; end if;

 -- Guarantee the seven generic metrics required by the controlled test.
 insert into public.hr_performance_metric_library(tenant_id,code,name,pillar,industry,unit,direction,description,default_target,default_weight,active) values
 (v_tenant,'GEN-OUTPUT','Target / Output Achievement','target_output','general','percent','higher_better','Achievement against agreed quantitative targets, deliverables or milestones.',90,20,true),
 (v_tenant,'GEN-DEADLINE','Deadline Delivery','target_output','general','percent','higher_better','Delivery of agreed work within committed timelines.',90,20,true),
 (v_tenant,'GEN-QUALITY','Work Quality & Accuracy','responsibility_quality','general','percent','higher_better','Accuracy, completeness, rework and quality of assigned responsibilities.',90,15,true),
 (v_tenant,'GEN-SOP','Responsibility / SOP Execution','responsibility_quality','general','percent','higher_better','Execution of job-description duties, procedures and controls.',90,15,true),
 (v_tenant,'GEN-ATTEND','Attendance & Punctuality','professional_conduct','general','percent','higher_better','Attendance and punctuality considered with authorised context.',95,10,true),
 (v_tenant,'GEN-TEAM','Collaboration & Communication','professional_conduct','general','score','higher_better','Teamwork, communication and constructive workplace behaviour.',4,10,true),
 (v_tenant,'GEN-CONDUCT','Professional Conduct & Ethics','professional_conduct','general','score','higher_better','Integrity, professionalism and adherence to organisational values.',4,10,true)
 on conflict(tenant_id,code) do update set name=excluded.name,pillar=excluded.pillar,industry=excluded.industry,unit=excluded.unit,direction=excluded.direction,description=excluded.description,default_target=excluded.default_target,default_weight=excluded.default_weight,active=true;

 insert into public.hr_performance_reviews(tenant_id,cycle_id,employee_id,status,plan_status,plan_activated_at)
 values(v_tenant,v_cycle,v_esi,'draft','activated',now()) on conflict(tenant_id,cycle_id,employee_id) do update set plan_status='activated',plan_activated_at=coalesce(public.hr_performance_reviews.plan_activated_at,now()) returning id into r_esi;
 insert into public.hr_performance_reviews(tenant_id,cycle_id,employee_id,status,plan_status,plan_activated_at,self_assessment_at,supervisor_assessment_at)
 values(v_tenant,v_cycle,v_ama,'reviewed','activated',now(),now(),now()) on conflict(tenant_id,cycle_id,employee_id) do update set status='reviewed',plan_status='activated',plan_activated_at=coalesce(public.hr_performance_reviews.plan_activated_at,now()),self_assessment_at=now(),supervisor_assessment_at=now() returning id into r_ama;
 insert into public.hr_performance_reviews(tenant_id,cycle_id,employee_id,status,plan_status,plan_activated_at,self_assessment_at,supervisor_assessment_at,completed_at,strengths,skill_gaps,recommended_action)
 values(v_tenant,v_cycle,v_kwame,'completed','closed',now(),now(),now(),now(),'Professional conduct, reliability and collaboration.','Target execution and work planning need improvement.','Training + mentoring + monitored Performance Improvement Plan.') on conflict(tenant_id,cycle_id,employee_id) do update set status='completed',plan_status='closed',completed_at=now(),strengths=excluded.strengths,skill_gaps=excluded.skill_gaps,recommended_action=excluded.recommended_action returning id into r_kwame;

 delete from public.hr_performance_checkins where tenant_id=v_tenant and review_id in(r_esi,r_ama,r_kwame);
 delete from public.hr_performance_decisions where tenant_id=v_tenant and review_id in(r_esi,r_ama,r_kwame);
 delete from public.hr_performance_improvement_plans where tenant_id=v_tenant and review_id in(r_esi,r_ama,r_kwame);
 delete from public.hr_performance_plan_items where tenant_id=v_tenant and review_id in(r_esi,r_ama,r_kwame);

 -- Esi baseline: 7 measures, total weight 100.
 insert into public.hr_performance_plan_items(tenant_id,review_id,metric_id,pillar,title,description,unit,direction,target_value,actual_value,weight,due_date,status)
 select v_tenant,r_esi,id,pillar,name,description,unit,direction,default_target,
 case code when 'GEN-OUTPUT' then 72 when 'GEN-DEADLINE' then 78 when 'GEN-QUALITY' then 84 when 'GEN-SOP' then 88 when 'GEN-ATTEND' then 96 else 4 end,
 default_weight,'2026-12-31',case when code in('GEN-OUTPUT','GEN-DEADLINE') then 'on_track' else 'planned' end
 from public.hr_performance_metric_library where tenant_id=v_tenant and code in('GEN-OUTPUT','GEN-DEADLINE','GEN-QUALITY','GEN-SOP','GEN-ATTEND','GEN-TEAM','GEN-CONDUCT');
 insert into public.hr_performance_checkins(tenant_id,review_id,checkin_date,progress_percent,status,achievements,blockers,support_required,next_actions,manager_comments) values
 (v_tenant,r_esi,'2026-04-30',32,'on_track','Core assignments delivered; attendance and teamwork strong.','Some delays obtaining source documents.','Earlier access to operational records.','Complete outstanding Q2 deliverables and document evidence.','Good start; maintain evidence for each target.'),
 (v_tenant,r_esi,'2026-07-31',58,'on_track','Quality improved and most deadlines met.','Competing operational priorities.','Priority clarification during peak periods.','Focus on target completion and reduce rework.','Progress is satisfactory with clear improvement.'),
 (v_tenant,r_esi,'2026-10-15',78,'on_track','Strong attendance, collaboration and SOP compliance.','Two deliverables remain behind schedule.','Weekly supervisor check-in until year end.','Close remaining deliverables before final appraisal.','On track overall; deadline discipline remains the key focus.');

 -- Ama assessment stage.
 insert into public.hr_performance_plan_items(tenant_id,review_id,metric_id,pillar,title,description,unit,direction,target_value,actual_value,weight,due_date,status,employee_score,supervisor_score,final_score,self_comments,supervisor_comments)
 select v_tenant,r_ama,id,pillar,name,description,unit,direction,default_target,
 case code when 'GEN-OUTPUT' then 88 when 'GEN-DEADLINE' then 86 when 'GEN-QUALITY' then 90 when 'GEN-SOP' then 91 when 'GEN-ATTEND' then 97 else 4 end,
 default_weight,'2026-12-31','on_track',
 case code when 'GEN-OUTPUT' then 94 when 'GEN-DEADLINE' then 90 when 'GEN-QUALITY' then 93 when 'GEN-SOP' then 92 when 'GEN-ATTEND' then 96 when 'GEN-TEAM' then 92 else 95 end,
 case code when 'GEN-OUTPUT' then 84 when 'GEN-DEADLINE' then 82 when 'GEN-QUALITY' then 86 when 'GEN-SOP' then 85 when 'GEN-ATTEND' then 95 when 'GEN-TEAM' then 88 else 90 end,
 case code when 'GEN-OUTPUT' then 84 when 'GEN-DEADLINE' then 82 when 'GEN-QUALITY' then 86 when 'GEN-SOP' then 85 when 'GEN-ATTEND' then 95 when 'GEN-TEAM' then 88 else 90 end,
 'Employee self-assessment: strong delivery and professional contribution.','Supervisor: strong overall performance; target evidence supports a slightly lower rating.'
 from public.hr_performance_metric_library where tenant_id=v_tenant and code in('GEN-OUTPUT','GEN-DEADLINE','GEN-QUALITY','GEN-SOP','GEN-ATTEND','GEN-TEAM','GEN-CONDUCT');
 -- Seed migrations run without an authenticated app user, so do not call the tenant-guarded RPC here.
 -- Calculate the same three-pillar score directly for the seeded review.
 update public.hr_performance_reviews r set
  target_output_score=x.a, responsibility_quality_score=x.b, professional_conduct_score=x.c,
  self_score=x.self_total, supervisor_score=x.total, final_score=x.total,
  final_rating=case when x.total>=90 then 'Exceptional' when x.total>=80 then 'Exceeds Expectations' when x.total>=65 then 'Meets Expectations' when x.total>=50 then 'Needs Improvement' else 'Unsatisfactory' end
 from (
  select
   round(coalesce(sum(final_score*weight) filter(where pillar='target_output')/nullif(sum(weight) filter(where pillar='target_output'),0),0),2) a,
   round(coalesce(sum(final_score*weight) filter(where pillar='responsibility_quality')/nullif(sum(weight) filter(where pillar='responsibility_quality'),0),0),2) b,
   round(coalesce(sum(final_score*weight) filter(where pillar='professional_conduct')/nullif(sum(weight) filter(where pillar='professional_conduct'),0),0),2) c,
   round(coalesce(sum(employee_score*weight)/nullif(sum(weight),0),0),2) self_total,
   round(coalesce(sum(final_score*weight)/nullif(sum(weight),0),0),2) total
  from public.hr_performance_plan_items where tenant_id=v_tenant and review_id=r_ama
 ) x where r.id=r_ama and r.tenant_id=v_tenant;

 -- Kwame completed development/PIP scenario.
 insert into public.hr_performance_plan_items(tenant_id,review_id,metric_id,pillar,title,description,unit,direction,target_value,actual_value,weight,due_date,status,employee_score,supervisor_score,final_score,self_comments,supervisor_comments)
 select v_tenant,r_kwame,id,pillar,name,description,unit,direction,default_target,
 case code when 'GEN-OUTPUT' then 58 when 'GEN-DEADLINE' then 62 when 'GEN-QUALITY' then 74 when 'GEN-SOP' then 78 when 'GEN-ATTEND' then 97 else 4 end,
 default_weight,'2026-12-31',case when code in('GEN-OUTPUT','GEN-DEADLINE') then 'at_risk' else 'on_track' end,
 case code when 'GEN-OUTPUT' then 70 when 'GEN-DEADLINE' then 68 when 'GEN-QUALITY' then 78 when 'GEN-SOP' then 80 when 'GEN-ATTEND' then 96 when 'GEN-TEAM' then 90 else 92 end,
 case code when 'GEN-OUTPUT' then 58 when 'GEN-DEADLINE' then 62 when 'GEN-QUALITY' then 74 when 'GEN-SOP' then 78 when 'GEN-ATTEND' then 96 when 'GEN-TEAM' then 90 else 92 end,
 case code when 'GEN-OUTPUT' then 58 when 'GEN-DEADLINE' then 62 when 'GEN-QUALITY' then 74 when 'GEN-SOP' then 78 when 'GEN-ATTEND' then 96 when 'GEN-TEAM' then 90 else 92 end,
 'Employee acknowledges target-delivery challenges but reports strong teamwork and reliability.','Supervisor confirms good conduct but identifies a material output and planning gap requiring structured support.'
 from public.hr_performance_metric_library where tenant_id=v_tenant and code in('GEN-OUTPUT','GEN-DEADLINE','GEN-QUALITY','GEN-SOP','GEN-ATTEND','GEN-TEAM','GEN-CONDUCT');
 -- Seed migrations run without an authenticated app user, so do not call the tenant-guarded RPC here.
 -- Calculate the same three-pillar score directly for the seeded review.
 update public.hr_performance_reviews r set
  target_output_score=x.a, responsibility_quality_score=x.b, professional_conduct_score=x.c,
  self_score=x.self_total, supervisor_score=x.total, final_score=x.total,
  final_rating=case when x.total>=90 then 'Exceptional' when x.total>=80 then 'Exceeds Expectations' when x.total>=65 then 'Meets Expectations' when x.total>=50 then 'Needs Improvement' else 'Unsatisfactory' end
 from (
  select
   round(coalesce(sum(final_score*weight) filter(where pillar='target_output')/nullif(sum(weight) filter(where pillar='target_output'),0),0),2) a,
   round(coalesce(sum(final_score*weight) filter(where pillar='responsibility_quality')/nullif(sum(weight) filter(where pillar='responsibility_quality'),0),0),2) b,
   round(coalesce(sum(final_score*weight) filter(where pillar='professional_conduct')/nullif(sum(weight) filter(where pillar='professional_conduct'),0),0),2) c,
   round(coalesce(sum(employee_score*weight)/nullif(sum(weight),0),0),2) self_total,
   round(coalesce(sum(final_score*weight)/nullif(sum(weight),0),0),2) total
  from public.hr_performance_plan_items where tenant_id=v_tenant and review_id=r_kwame
 ) x where r.id=r_kwame and r.tenant_id=v_tenant;
 update public.hr_performance_reviews set status='completed',plan_status='closed',completed_at=now() where id=r_kwame;
 insert into public.hr_performance_decisions(tenant_id,review_id,action_type,rationale,status) values
 (v_tenant,r_kwame,'training','Output is below expectation while conduct remains strong; targeted development is appropriate.','approved'),
 (v_tenant,r_kwame,'mentoring','Provide structured work-planning and prioritisation support.','approved'),
 (v_tenant,r_kwame,'pip','Use measurable improvement targets and scheduled supervisor reviews.','approved');
 insert into public.hr_performance_improvement_plans(tenant_id,employee_id,review_id,title,objectives,actions_support,start_date,review_date,status)
 values(v_tenant,v_kwame,r_kwame,'2026 Target Delivery Improvement Plan','Improve target completion and deadline delivery to at least 80% while maintaining professional conduct.','Weekly supervisor planning review; prioritisation coaching; targeted training; monthly evidence-based progress review.','2026-10-23','2026-12-23','open');

 -- Self-verification. Any mismatch aborts the migration rather than reporting false success.
 select count(*),coalesce(sum(weight),0) into n,w from public.hr_performance_plan_items where review_id=r_esi;
 if n<>7 or w<>100 then raise exception '010g verification failed for Esi: expected 7 measures / 100 weight, got % / %',n,w; end if;
 select count(*) into n from public.hr_performance_checkins where review_id=r_esi; if n<>3 then raise exception '010g verification failed for Esi check-ins: expected 3, got %',n; end if;
 select count(*) into n from public.hr_performance_plan_items where review_id=r_ama and employee_score is not null and supervisor_score is not null; if n<>7 then raise exception '010g verification failed for Ama assessments: expected 7, got %',n; end if;
 select count(*) into n from public.hr_performance_plan_items where review_id=r_kwame and final_score is not null; if n<>7 then raise exception '010g verification failed for Kwame scorecard: expected 7, got %',n; end if;
 select count(*) into n from public.hr_performance_decisions where review_id=r_kwame; if n<>3 then raise exception '010g verification failed for Kwame decisions: expected 3, got %',n; end if;
 select count(*) into n from public.hr_performance_improvement_plans where review_id=r_kwame and status='open'; if n<>1 then raise exception '010g verification failed for Kwame PIP: expected 1 open PIP, got %',n; end if;
 raise notice '010g verified: Esi 7/100 + 3 check-ins; Ama 7 assessed; Kwame 7 completed + 3 decisions + PIP.';
end $$;
