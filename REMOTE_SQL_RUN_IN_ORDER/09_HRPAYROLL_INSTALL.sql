-- CONTINUATION: UniMIS Build 172 HR/Payroll repair
set search_path=unimis,public;

-- SOURCE 202610260945_011r_continue_existing_checkin.sql
-- 011r: continue an existing scheduled check-in instead of trying to create a duplicate period.
-- One scheduled check-in is the parent record; KPI results/evidence are added or updated beneath it.
-- Already verified/system-verified facts are preserved. ADHOC check-ins remain repeatable.

create or replace function unimis.hr_performance_record_period_checkin(
 p_tenant uuid,p_review uuid,p_period_key text,p_period_label text,p_period_start date,p_period_end date,p_checkin_date date,
 p_status text,p_actual_progress text,p_achievements text,p_blockers text,p_evidence text,p_support_required text,p_next_actions text,p_measures jsonb
) returns jsonb language plpgsql security definer set search_path=unimis as $$
declare v_checkin uuid; v_existing_item uuid; v_existing_verification text; m jsonb; v_item uuid; v_actual numeric; v_progress numeric; v_reviewer uuid; v_type text; v_source text; v_verification text; v_reused boolean:=false;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select reviewer_employee_id into v_reviewer from hrc_hr_performance_reviews where tenant_id=p_tenant and id=p_review and plan_status='activated' and coalesce(finalization_status,'draft')<>'finalized';
 if not found then raise exception 'Review must be activated and not finalized'; end if;
 if coalesce(trim(p_period_key),'')='' then raise exception 'Check-in period is required'; end if;
 if p_period_start is not null and p_period_end is not null and p_period_end<p_period_start then raise exception 'Check-in period end date cannot be before its start date'; end if;
 if p_status not in ('on_track','at_risk','off_track','exceeded') then raise exception 'Invalid check-in status'; end if;
 if upper(p_period_key)<>'ADHOC' then
  select id into v_checkin from hrc_hr_performance_checkins
   where tenant_id=p_tenant and review_id=p_review and period_key=p_period_key
   order by created_at asc limit 1;
 end if;
 if v_checkin is null then
  insert into hrc_hr_performance_checkins(tenant_id,review_id,checkin_date,period_key,period_label,period_start,period_end,reviewer_employee_id,progress_percent,status,actual_progress,achievements,blockers,evidence,support_required,next_actions)
  values(p_tenant,p_review,coalesce(p_checkin_date,current_date),p_period_key,coalesce(nullif(trim(p_period_label),''),p_period_key),p_period_start,p_period_end,v_reviewer,null,p_status,nullif(trim(p_actual_progress),''),nullif(trim(p_achievements),''),nullif(trim(p_blockers),''),nullif(trim(p_evidence),''),nullif(trim(p_support_required),''),nullif(trim(p_next_actions),'')) returning id into v_checkin;
 else
  v_reused:=true;
  update hrc_hr_performance_checkins set
   status=p_status, reviewer_employee_id=coalesce(reviewer_employee_id,v_reviewer),
   actual_progress=coalesce(nullif(trim(p_actual_progress),''),actual_progress),
   achievements=coalesce(nullif(trim(p_achievements),''),achievements),
   blockers=coalesce(nullif(trim(p_blockers),''),blockers),
   evidence=coalesce(nullif(trim(p_evidence),''),evidence),
   support_required=coalesce(nullif(trim(p_support_required),''),support_required),
   next_actions=coalesce(nullif(trim(p_next_actions),''),next_actions)
  where id=v_checkin and tenant_id=p_tenant;
 end if;
 for m in select * from jsonb_array_elements(coalesce(p_measures,'[]'::jsonb)) loop
  v_item=nullif(m->>'item_id','')::uuid; v_actual=nullif(m->>'actual_value','')::numeric;
  if v_item is not null and v_actual is not null then
   select coalesce(pi.measurement_type_snapshot,ml.measurement_type,'numeric'),coalesce(pi.data_source_snapshot,ml.data_source,'manager_verified') into v_type,v_source
   from hrc_hr_performance_plan_items pi left join hrc_hr_performance_metric_library ml on ml.id=pi.metric_id
   where pi.id=v_item and pi.tenant_id=p_tenant and pi.review_id=p_review;
   if not found then raise exception 'Invalid performance measure in check-in'; end if;
   v_verification=case when v_type='system_calculated' then 'system_verified' when v_type='behavioral_rubric' then 'manager_attested' else 'pending' end;
   if v_verification='pending' and coalesce(trim(m->>'evidence'),'')='' and not exists(select 1 from hrc_hr_performance_evidence_attachments a where a.tenant_id=p_tenant and a.review_id=p_review and a.plan_item_id=v_item) then
    raise exception 'Objective/manual source figures require evidence before submission';
   end if;
   v_existing_item:=null; v_existing_verification:=null;
   select id,verification_status into v_existing_item,v_existing_verification
    from hrc_hr_performance_checkin_items where tenant_id=p_tenant and checkin_id=v_checkin and plan_item_id=v_item
    order by created_at desc limit 1;
   if v_existing_item is null then
    insert into hrc_hr_performance_checkin_items(tenant_id,checkin_id,review_id,plan_item_id,actual_value,evidence,evidence_source,measurement_inputs,measurement_type,verification_status)
    values(p_tenant,v_checkin,p_review,v_item,v_actual,nullif(trim(m->>'evidence'),''),coalesce(nullif(m->>'evidence_source',''),case when v_source='operational_record' then 'system_record' else 'manager_observation' end),coalesce(m->'measurement_inputs','{}'::jsonb),v_type,v_verification);
   elsif v_existing_verification in ('verified','system_verified') then
    null; -- preserve already verified facts; continuing the check-in must never overwrite them
   else
    update hrc_hr_performance_checkin_items set actual_value=v_actual,evidence=nullif(trim(m->>'evidence'),''),
     evidence_source=coalesce(nullif(m->>'evidence_source',''),case when v_source='operational_record' then 'system_record' else 'manager_observation' end),
     measurement_inputs=coalesce(m->'measurement_inputs','{}'::jsonb),measurement_type=v_type,verification_status=v_verification,verified_by=null,verified_at=null,verification_note=null
    where id=v_existing_item;
   end if;
  end if;
 end loop;
 perform unimis.hr_performance_refresh_intelligence(p_tenant,p_review);
 select case when coalesce(sum(weight) filter(where system_score is not null),0)=0 then null else round(sum(system_score*weight) filter(where system_score is not null)/sum(weight) filter(where system_score is not null),2) end into v_progress from hrc_hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review;
 perform unimis.hr_refresh_checkin_verified_progress(p_tenant,v_checkin);
 update hrc_hr_performance_checkins set progress_percent=current_verified_progress_percent, recorded_progress_percent=current_verified_progress_percent where id=v_checkin;
 select current_verified_progress_percent into v_progress from hrc_hr_performance_checkins where id=v_checkin;
 return jsonb_build_object('checkin_id',v_checkin,'progress_percent',v_progress,'period',p_period_label,'verification_required',true,'reused_existing',v_reused);
end $$;
grant execute on function unimis.hr_performance_record_period_checkin(uuid,uuid,text,text,date,date,date,text,text,text,text,text,text,text,jsonb) to authenticated;


-- SOURCE 202610261030_011t_checkin_summary_finalization.sql
-- 011t: check-in summary and finalization lifecycle.
alter table unimis.hrc_hr_performance_checkins
 add column if not exists finalization_status text not null default 'open',
 add column if not exists finalized_at timestamptz,
 add column if not exists finalized_by uuid,
 add column if not exists status_override_reason text;

do $$ begin
 if not exists(select 1 from pg_constraint where conname='hr_performance_checkins_finalization_status_check') then
  alter table unimis.hrc_hr_performance_checkins add constraint hr_performance_checkins_finalization_status_check check(finalization_status in ('open','finalized'));
 end if;
end $$;

-- Recorded Progress is a frozen finalization snapshot, not a live value.
update unimis.hrc_hr_performance_checkins set recorded_progress_percent=null
where finalization_status='open';

create or replace function unimis.hr_save_performance_checkin_summary(
 p_tenant uuid,p_checkin uuid,p_status text,p_actual_progress text,p_achievements text,p_blockers text,p_evidence text,p_support_required text,p_next_actions text,p_override_reason text default null
) returns jsonb language plpgsql security definer set search_path=unimis as $$
declare c record; v_suggested text;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select * into c from hrc_hr_performance_checkins where tenant_id=p_tenant and id=p_checkin for update;
 if not found then raise exception 'Check-in not found'; end if;
 if c.finalization_status='finalized' then raise exception 'This check-in is finalized and locked'; end if;
 if p_status not in ('on_track','at_risk','off_track','exceeded') then raise exception 'Invalid check-in status'; end if;
 if length(coalesce(trim(p_actual_progress),''))<10 then raise exception 'Add a brief overall progress/result summary'; end if;
 if coalesce(c.verified_measure_count,0)=coalesce(c.total_measure_count,0) and coalesce(c.total_measure_count,0)>0 then
  v_suggested=case when coalesce(c.current_verified_progress_percent,0)>=100 then 'exceeded' when c.current_verified_progress_percent>=75 then 'on_track' when c.current_verified_progress_percent>=50 then 'at_risk' else 'off_track' end;
 end if;
 if v_suggested is not null and p_status<>v_suggested and length(coalesce(trim(p_override_reason),''))<10 then raise exception 'Explain why the supervisor status differs from the system suggestion'; end if;
 update hrc_hr_performance_checkins set status=p_status,actual_progress=nullif(trim(p_actual_progress),''),achievements=nullif(trim(p_achievements),''),blockers=nullif(trim(p_blockers),''),evidence=nullif(trim(p_evidence),''),support_required=nullif(trim(p_support_required),''),next_actions=nullif(trim(p_next_actions),''),status_override_reason=case when v_suggested is not null and p_status<>v_suggested then nullif(trim(p_override_reason),'') else null end where id=p_checkin and tenant_id=p_tenant;
 return jsonb_build_object('checkin_id',p_checkin,'suggested_status',v_suggested,'status',p_status,'summary_saved',true);
end $$;
grant execute on function unimis.hr_save_performance_checkin_summary(uuid,uuid,text,text,text,text,text,text,text,text) to authenticated;

create or replace function unimis.hr_finalize_performance_checkin(p_tenant uuid,p_checkin uuid) returns jsonb
language plpgsql security definer set search_path=unimis as $$
declare c record;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select * into c from hrc_hr_performance_checkins where tenant_id=p_tenant and id=p_checkin for update;
 if not found then raise exception 'Check-in not found'; end if;
 if c.finalization_status='finalized' then return jsonb_build_object('checkin_id',p_checkin,'already_finalized',true,'recorded_progress_percent',c.recorded_progress_percent); end if;
 perform unimis.hr_refresh_checkin_verified_progress(p_tenant,p_checkin);
 select * into c from hrc_hr_performance_checkins where tenant_id=p_tenant and id=p_checkin for update;
 if coalesce(c.total_measure_count,0)=0 or coalesce(c.verified_measure_count,0)<>c.total_measure_count then raise exception 'All performance measures must be verified before finalizing this check-in (% of % verified)',coalesce(c.verified_measure_count,0),coalesce(c.total_measure_count,0); end if;
 if length(coalesce(trim(c.actual_progress),''))<10 then raise exception 'Complete the Check-in Summary before finalizing'; end if;
 update hrc_hr_performance_checkins set recorded_progress_percent=current_verified_progress_percent,progress_percent=current_verified_progress_percent,finalization_status='finalized',finalized_at=now(),finalized_by=auth.uid() where tenant_id=p_tenant and id=p_checkin;
 return jsonb_build_object('checkin_id',p_checkin,'finalized',true,'recorded_progress_percent',c.current_verified_progress_percent);
end $$;
grant execute on function unimis.hr_finalize_performance_checkin(uuid,uuid) to authenticated;

-- 011r continuation, corrected: live evidence refresh must not overwrite Recorded Progress.
create or replace function unimis.hr_performance_record_period_checkin(
 p_tenant uuid,p_review uuid,p_period_key text,p_period_label text,p_period_start date,p_period_end date,p_checkin_date date,
 p_status text,p_actual_progress text,p_achievements text,p_blockers text,p_evidence text,p_support_required text,p_next_actions text,p_measures jsonb
) returns jsonb language plpgsql security definer set search_path=unimis as $$
declare v_checkin uuid; v_existing_item uuid; v_existing_verification text; m jsonb; v_item uuid; v_actual numeric; v_progress numeric; v_reviewer uuid; v_type text; v_source text; v_verification text; v_reused boolean:=false; v_final text;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select reviewer_employee_id into v_reviewer from hrc_hr_performance_reviews where tenant_id=p_tenant and id=p_review and plan_status='activated' and coalesce(finalization_status,'draft')<>'finalized';
 if not found then raise exception 'Review must be activated and not finalized'; end if;
 if coalesce(trim(p_period_key),'')='' then raise exception 'Check-in period is required'; end if;
 if p_period_start is not null and p_period_end is not null and p_period_end<p_period_start then raise exception 'Check-in period end date cannot be before its start date'; end if;
 if p_status not in ('on_track','at_risk','off_track','exceeded') then raise exception 'Invalid check-in status'; end if;
 if upper(p_period_key)<>'ADHOC' then select id,finalization_status into v_checkin,v_final from hrc_hr_performance_checkins where tenant_id=p_tenant and review_id=p_review and period_key=p_period_key order by created_at asc limit 1; end if;
 if v_final='finalized' then raise exception 'This check-in period is finalized and locked'; end if;
 if v_checkin is null then insert into hrc_hr_performance_checkins(tenant_id,review_id,checkin_date,period_key,period_label,period_start,period_end,reviewer_employee_id,progress_percent,status) values(p_tenant,p_review,coalesce(p_checkin_date,current_date),p_period_key,coalesce(nullif(trim(p_period_label),''),p_period_key),p_period_start,p_period_end,v_reviewer,null,p_status) returning id into v_checkin; else v_reused:=true; end if;
 for m in select * from jsonb_array_elements(coalesce(p_measures,'[]'::jsonb)) loop
  v_item=nullif(m->>'item_id','')::uuid; v_actual=nullif(m->>'actual_value','')::numeric;
  if v_item is not null and v_actual is not null then
   select coalesce(pi.measurement_type_snapshot,ml.measurement_type,'numeric'),coalesce(pi.data_source_snapshot,ml.data_source,'manager_verified') into v_type,v_source from hrc_hr_performance_plan_items pi left join hrc_hr_performance_metric_library ml on ml.id=pi.metric_id where pi.id=v_item and pi.tenant_id=p_tenant and pi.review_id=p_review;
   if not found then raise exception 'Invalid performance measure in check-in'; end if;
   v_verification=case when v_type='system_calculated' then 'system_verified' when v_type='behavioral_rubric' then 'manager_attested' else 'pending' end;
   if v_verification='pending' and coalesce(trim(m->>'evidence'),'')='' and not exists(select 1 from hrc_hr_performance_evidence_attachments a where a.tenant_id=p_tenant and a.review_id=p_review and a.plan_item_id=v_item) then raise exception 'Objective/manual source figures require evidence before submission'; end if;
   v_existing_item:=null;v_existing_verification:=null;
   select id,verification_status into v_existing_item,v_existing_verification from hrc_hr_performance_checkin_items where tenant_id=p_tenant and checkin_id=v_checkin and plan_item_id=v_item order by created_at desc limit 1;
   if v_existing_item is null then insert into hrc_hr_performance_checkin_items(tenant_id,checkin_id,review_id,plan_item_id,actual_value,evidence,evidence_source,measurement_inputs,measurement_type,verification_status) values(p_tenant,v_checkin,p_review,v_item,v_actual,nullif(trim(m->>'evidence'),''),coalesce(nullif(m->>'evidence_source',''),case when v_source='operational_record' then 'system_record' else 'manager_observation' end),coalesce(m->'measurement_inputs','{}'::jsonb),v_type,v_verification);
   elsif v_existing_verification in ('verified','system_verified') then null;
   else update hrc_hr_performance_checkin_items set actual_value=v_actual,evidence=nullif(trim(m->>'evidence'),''),evidence_source=coalesce(nullif(m->>'evidence_source',''),case when v_source='operational_record' then 'system_record' else 'manager_observation' end),measurement_inputs=coalesce(m->'measurement_inputs','{}'::jsonb),measurement_type=v_type,verification_status=v_verification,verified_by=null,verified_at=null,verification_note=null where id=v_existing_item; end if;
  end if;
 end loop;
 perform unimis.hr_performance_refresh_intelligence(p_tenant,p_review); perform unimis.hr_refresh_checkin_verified_progress(p_tenant,v_checkin);
 update hrc_hr_performance_checkins set progress_percent=current_verified_progress_percent where id=v_checkin;
 select current_verified_progress_percent into v_progress from hrc_hr_performance_checkins where id=v_checkin;
 return jsonb_build_object('checkin_id',v_checkin,'progress_percent',v_progress,'period',p_period_label,'verification_required',true,'reused_existing',v_reused);
end $$;
grant execute on function unimis.hr_performance_record_period_checkin(uuid,uuid,text,text,date,date,date,text,text,text,text,text,text,text,jsonb) to authenticated;


-- SOURCE 202610261045_012_performance_intelligence_simulation_foundation.sql
-- 012 Performance Intelligence & multi-industry simulation foundation
create table if not exists unimis.hrc_hr_performance_simulation_cases (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
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

alter table unimis.hrc_hr_performance_simulation_cases enable row level security;
drop policy if exists hr_performance_simulation_cases_member on unimis.hrc_hr_performance_simulation_cases;
create policy hr_performance_simulation_cases_member on unimis.hrc_hr_performance_simulation_cases
for all using (unimis.is_tenant_member(tenant_id)) with check (unimis.is_tenant_member(tenant_id));

create or replace function unimis.hr_seed_performance_intelligence_simulations(p_tenant uuid)
returns jsonb language plpgsql security definer set search_path=unimis as $$
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 insert into unimis.hrc_hr_performance_simulation_cases
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

grant execute on function unimis.hr_seed_performance_intelligence_simulations(uuid) to authenticated;


-- SOURCE 202610261100_012b_leave_aware_performance_intelligence.sql
-- 012b Leave-aware Performance Intelligence simulation extension
alter table unimis.hrc_hr_performance_simulation_cases add column if not exists approved_leave_days numeric(7,2) not null default 0;
alter table unimis.hrc_hr_performance_simulation_cases add column if not exists adjusted_attendance_percent numeric(6,2);
alter table unimis.hrc_hr_performance_simulation_cases add column if not exists leave_intelligence text;
alter table unimis.hrc_hr_performance_simulation_cases add column if not exists employee_participation_status text not null default 'not_started';
alter table unimis.hrc_hr_performance_simulation_cases add column if not exists assessment_readiness text not null default 'system_prepared';

create or replace function unimis.hr_seed_performance_intelligence_simulations(p_tenant uuid)
returns jsonb language plpgsql security definer set search_path=unimis as $$
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 insert into unimis.hrc_hr_performance_simulation_cases
 (tenant_id,sector,organization_name,employee_name,role_title,scenario_code,objective_score,attendance_percent,manager_rating,evidence_completeness,employee_reflection,intelligence_summary,exception_flags,recommended_action,policy_gate,approved_leave_days,adjusted_attendance_percent,leave_intelligence,employee_participation_status,assessment_readiness)
 values
 (p_tenant,'Trading','Aseda Trading Ltd','Adwoa Mensah','Sales Officer','TRADING-HIGH',96.4,97,4.6,100,'Exceeded my sales and collection targets and supported two new accounts.','Strong objective performance with complete evidence. Manager rating is aligned with operational results.','[]','Recognize performance; consider stretch targets and succession readiness.','Eligible subject to time-in-grade and approved vacancy.',3,98.2,'Three approved leave days were excluded from attendance penalty. No leave-related concern.','submitted','ready'),
 (p_tenant,'Trading','Aseda Trading Ltd','Kwame Boateng','Storekeeper','TRADING-BIAS',91.2,96,2.4,100,'Stock counts improved and variances reduced during the period.','Objective evidence is strong but the manager rating is materially lower. Calibration review is recommended before finalization.','["manager_objective_mismatch"]','Route to HR calibration; do not auto-adjust the rating.','Decision held pending calibration.',2,96.8,'Approved leave is reconciled. The exception is the manager/objective mismatch, not attendance.','submitted','calibration_required'),
 (p_tenant,'Education','Apex Technical College','Efua Owusu','Lecturer','EDU-BALANCED',88.5,94,4.1,95,'Completed teaching plan and practical assessments; requested support for digital content.','Good teaching delivery with a minor attendance gap and a clear development request.','["attendance_below_target"]','Coaching plus digital-learning development plan.','No adverse decision; development action recommended.',6,96.8,'Six approved leave days were excluded. Adjusted attendance improves to 96.8%; no adverse leave inference should be made.','submitted','ready'),
 (p_tenant,'NGO','HopeBridge Foundation','Yaw Asare','Project Officer','NGO-EVIDENCE',92.0,98,4.3,62,'Field milestones were completed but several beneficiary reports are still being uploaded.','Reported outcomes are strong, but evidence completeness is insufficient for a high-confidence final assessment.','["evidence_gap"]','Request missing field evidence before assessment finalization.','Final score remains provisional until evidence threshold is met.',4,99.0,'Approved field/leave days are reconciled and do not explain the evidence gap.','submitted','evidence_required'),
 (p_tenant,'Healthcare','Akwaaba Community Hospital','Akosua Frimpong','Records Officer','HEALTH-QUALITY',84.0,99,4.0,100,'Improved records turnaround but documentation errors remain a concern.','Attendance and conduct are strong; quality indicators show a recurring documentation issue.','["quality_risk"]','Targeted records-quality coaching and 60-day follow-up.','No PIP unless quality remains below policy threshold.',8,99.0,'Eight approved leave days are neutral to performance. Quality, not leave, drives the exception.','submitted','supervisor_review'),
 (p_tenant,'Manufacturing','Prime Manufacturing Ltd','Kofi Antwi','Maintenance Technician','MFG-PIP',67.5,88,2.8,100,'Downtime response improved late in the period after additional coaching.','Multiple objective indicators remain below threshold despite complete evidence. Improvement is visible but not yet sustained.','["performance_below_threshold","attendance_risk"]','Supervisor review for structured PIP with measurable 60-day milestones.','PIP eligible; disciplinary action is not automatic.',1,88.4,'Only one approved leave day exists; low attendance remains a genuine exception after adjustment.','submitted','supervisor_review'),
 (p_tenant,'Hospitality','Akwaba Hotel','Mabel Addo','Front Desk Officer','HOTEL-PROMO-GATE',95.0,98,4.7,100,'Guest feedback and reservation accuracy were strong throughout the period.','High performance and strong service evidence. Promotion readiness is positive, but policy eligibility must still be checked.','["promotion_policy_gate"]','Place in talent pool; check time-in-grade before promotion approval.','Not yet eligible: minimum time-in-grade not satisfied.',5,99.1,'Approved leave is reconciled with no adverse attendance effect.','submitted','policy_check')
 on conflict (tenant_id,scenario_code) do update set
 objective_score=excluded.objective_score,attendance_percent=excluded.attendance_percent,manager_rating=excluded.manager_rating,evidence_completeness=excluded.evidence_completeness,employee_reflection=excluded.employee_reflection,intelligence_summary=excluded.intelligence_summary,exception_flags=excluded.exception_flags,recommended_action=excluded.recommended_action,policy_gate=excluded.policy_gate,approved_leave_days=excluded.approved_leave_days,adjusted_attendance_percent=excluded.adjusted_attendance_percent,leave_intelligence=excluded.leave_intelligence,employee_participation_status=excluded.employee_participation_status,assessment_readiness=excluded.assessment_readiness;
 return jsonb_build_object('ok',true,'cases',7,'leave_aware',true);
end $$;
grant execute on function unimis.hr_seed_performance_intelligence_simulations(uuid) to authenticated;


-- SOURCE 202610261115_012c_adaptive_sector_simulation.sql
-- 012c Adaptive sector simulations: retain existing seed then extend it.
alter function unimis.hr_seed_performance_intelligence_simulations(uuid) rename to hr_seed_performance_intelligence_simulations_012b;

create or replace function unimis.hr_seed_performance_intelligence_simulations(p_tenant uuid)
returns jsonb language plpgsql security definer set search_path=unimis as $$
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 perform unimis.hr_seed_performance_intelligence_simulations_012b(p_tenant);
 insert into unimis.hrc_hr_performance_simulation_cases
 (tenant_id,sector,organization_name,employee_name,role_title,scenario_code,objective_score,attendance_percent,manager_rating,evidence_completeness,employee_reflection,intelligence_summary,exception_flags,recommended_action,policy_gate,approved_leave_days,adjusted_attendance_percent,leave_intelligence,employee_participation_status,assessment_readiness) values
 (p_tenant,'Banking & Financial Services','Adom Rural Bank','Nana Osei','Credit Officer','BANK-CREDIT-RISK',89.0,96,4.1,100,'Collections improved, but two assigned facilities require closer follow-up.','Overall delivery is sound. Portfolio arrears require focused review before advancement decisions.','["portfolio_risk"]','Review arrears trend, recovery actions and documentation; set a 60-day portfolio follow-up.','No adverse employment decision is automatic; credit-risk evidence requires supervisor review.',4,97.2,'Approved leave is excluded. Attendance is not the source of the banking exception.','submitted','supervisor_review'),
 (p_tenant,'Broadcasting & Media','Unity FM','Abena Serwaa','Programs Producer','FM-PROGRAMS',93.0,95,4.4,92,'Delivered scheduled programmes and improved guest coordination; some programme logs remain outstanding.','Strong programme delivery with a small evidence/documentation gap in broadcast logs.','["evidence_gap"]','Complete programme logs and retain broadcast evidence before final assessment.','Content quality and compliance remain human-reviewed.',3,96.1,'Approved leave is reconciled and does not create an attendance penalty.','submitted','evidence_required'),
 (p_tenant,'General / Other','Adaptive Services Ltd','Daniel Mensah','Operations Officer','GENERAL-ADAPTIVE',87.0,97,4.0,90,'Completed core responsibilities and requested clearer targets for the next cycle.','General-purpose profile demonstrates the adaptive fallback when no specialist industry template exists.','["kpi_template_review"]','Use organization, department and position context to recommend editable KPIs for the next cycle.','General template remains configurable; HR approves organization-specific measures.',2,97.8,'Approved leave is neutral. Organization policy determines attendance thresholds.','submitted','ready')
 on conflict (tenant_id,scenario_code) do update set objective_score=excluded.objective_score,attendance_percent=excluded.attendance_percent,manager_rating=excluded.manager_rating,evidence_completeness=excluded.evidence_completeness,employee_reflection=excluded.employee_reflection,intelligence_summary=excluded.intelligence_summary,exception_flags=excluded.exception_flags,recommended_action=excluded.recommended_action,policy_gate=excluded.policy_gate,approved_leave_days=excluded.approved_leave_days,adjusted_attendance_percent=excluded.adjusted_attendance_percent,leave_intelligence=excluded.leave_intelligence,employee_participation_status=excluded.employee_participation_status,assessment_readiness=excluded.assessment_readiness;
 return jsonb_build_object('ok',true,'cases',10,'adaptive',true,'sectors',9);
end $$;
grant execute on function unimis.hr_seed_performance_intelligence_simulations(uuid) to authenticated;


-- SOURCE 202610271230_013_performance_automation_engine.sql
-- 013 Performance Automation Engine
-- Universal evidence model: KPI + Task/SLA + Work Standard + Compliance + Competency + Attendance.

alter table unimis.hrc_hr_performance_metric_library add column if not exists measurement_class text not null default 'kpi';
alter table unimis.hrc_hr_performance_metric_library add column if not exists measurement_frequency text not null default 'monthly';
alter table unimis.hrc_hr_performance_metric_library add column if not exists source_type text not null default 'verified_evidence';
alter table unimis.hrc_hr_performance_metric_library add column if not exists verification_rule text not null default 'supervisor_review';
alter table unimis.hrc_hr_performance_metric_library add column if not exists formula_expression text;

create table if not exists unimis.hrc_hr_performance_templates(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 code text not null, name text not null, industry text not null default 'general', department_name text,
 position_title text not null, grade_name text, description text, active boolean not null default true,
 created_at timestamptz not null default now(), unique(tenant_id,code)
);
create table if not exists unimis.hrc_hr_performance_template_items(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 template_id uuid not null references unimis.hrc_hr_performance_templates(id) on delete cascade,
 code text not null, name text not null, measurement_class text not null,
 target_value numeric(14,2), unit text not null default 'percent', direction text not null default 'higher_better',
 weight numeric(6,2) not null, frequency text not null default 'monthly', source_type text not null,
 verification_rule text not null default 'system_or_supervisor', formula_expression text, display_order int not null default 10,
 unique(template_id,code)
);
create table if not exists unimis.hrc_hr_performance_data_sources(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 code text not null, name text not null, source_type text not null, trust_level text not null default 'verified',
 status text not null default 'active', description text, last_sync_at timestamptz, created_at timestamptz not null default now(),
 unique(tenant_id,code)
);
create table if not exists unimis.hrc_hr_performance_ledger(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 employee_ref text not null, employee_name text not null, position_title text, grade_name text,
 period_key text not null, fact_code text not null, fact_name text not null, measurement_class text not null,
 actual_value numeric(14,2), target_value numeric(14,2), unit text, direction text not null default 'higher_better',
 source_code text not null, verification_status text not null default 'system_verified', evidence_note text,
 observed_at date not null, created_at timestamptz not null default now(), unique(tenant_id,employee_ref,period_key,fact_code)
);
create table if not exists unimis.hrc_hr_automated_checkins(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 employee_ref text not null, employee_name text not null, period_key text not null, period_label text not null,
 prepared_score numeric(6,2), status text not null default 'prepared', exception_count int not null default 0,
 exception_summary text, employee_response text, supervisor_response text, prepared_at timestamptz not null default now(),
 unique(tenant_id,employee_ref,period_key)
);

do $$ declare t text; begin
 foreach t in array array['hrc_hr_performance_templates','hrc_hr_performance_template_items','hrc_hr_performance_data_sources','hrc_hr_performance_ledger','hrc_hr_automated_checkins'] loop
  execute format('alter table unimis.%I enable row level security',t);
  execute format('drop policy if exists tenant_member_all on unimis.%I',t);
  execute format('create policy tenant_member_all on unimis.%I for all using (unimis.is_tenant_member(tenant_id)) with check (unimis.is_tenant_member(tenant_id))',t);
 end loop;
end $$;

create index if not exists idx_perf_ledger_employee_period on unimis.hrc_hr_performance_ledger(tenant_id,employee_ref,period_key);
create index if not exists idx_auto_checkins_period on unimis.hrc_hr_automated_checkins(tenant_id,period_key,status);

create or replace function unimis.hr_seed_bank_performance_automation(p_tenant uuid) returns jsonb language plpgsql security definer set search_path=unimis as $$
declare tpl uuid; r record; p text; d date; disb numeric; npl numeric; tat numeric; kyc numeric; att numeric; sc numeric; exc int;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 insert into hrc_hr_performance_templates(tenant_id,code,name,industry,department_name,position_title,grade_name,description)
 values(p_tenant,'BANK-CREDIT-G3','Grade 3 Credit Officer Performance Template','banking','Credit','Credit Officer','Grade 3','Reference template proving position/grade performance automation for Adom Rural Bank.')
 on conflict(tenant_id,code) do update set name=excluded.name,description=excluded.description returning id into tpl;
 if tpl is null then select id into tpl from hrc_hr_performance_templates where tenant_id=p_tenant and code='BANK-CREDIT-G3'; end if;
 insert into hrc_hr_performance_template_items(tenant_id,template_id,code,name,measurement_class,target_value,unit,direction,weight,frequency,source_type,verification_rule,formula_expression,display_order) values
 (p_tenant,tpl,'DISB','Loan Disbursement Volume','kpi',500000,'GHS','higher_better',25,'quarterly','import_or_api','trusted_source','actual / target * 100',10),
 (p_tenant,tpl,'NPL','NPL Ratio','kpi',3,'percent','lower_better',20,'monthly','import_or_api','trusted_source','target / actual * 100 capped at 100',20),
 (p_tenant,tpl,'TAT','Loan Turnaround Time','task_sla',48,'hours','lower_better',15,'monthly','workflow_or_import','trusted_source','target / actual * 100 capped at 100',30),
 (p_tenant,tpl,'KYC','KYC / Site Visit Accuracy','compliance',100,'percent','higher_better',15,'monthly','checklist_or_import','compliance_review','actual / target * 100',40),
 (p_tenant,tpl,'ATT','Attendance & Punctuality','attendance',95,'percent','higher_better',10,'monthly','hr_attendance','system_verified','leave-adjusted attendance',50),
 (p_tenant,tpl,'CONDUCT','Professional Conduct & Service','competency',4,'score_5','higher_better',15,'quarterly','anchored_observation','supervisor_review','anchored 1-5 rubric',60)
 on conflict(template_id,code) do update set name=excluded.name,measurement_class=excluded.measurement_class,target_value=excluded.target_value,weight=excluded.weight,source_type=excluded.source_type;
 insert into hrc_hr_performance_data_sources(tenant_id,code,name,source_type,trust_level,description) values
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
  insert into hrc_hr_performance_ledger(tenant_id,employee_ref,employee_name,position_title,grade_name,period_key,fact_code,fact_name,measurement_class,actual_value,target_value,unit,direction,source_code,verification_status,evidence_note,observed_at) values
  (p_tenant,'BANK-KM-001','Kojo Mensah','Credit Officer','Grade 3',p,'DISB','Loan Disbursement Volume','kpi',disb,166666.67,'GHS','higher_better','BANK-CSV','system_verified','Imported core banking operational fact',d),
  (p_tenant,'BANK-KM-001','Kojo Mensah','Credit Officer','Grade 3',p,'NPL','NPL Ratio','kpi',npl,3,'percent','lower_better','BANK-CSV','system_verified','Portfolio quality extract',d),
  (p_tenant,'BANK-KM-001','Kojo Mensah','Credit Officer','Grade 3',p,'TAT','Loan Turnaround Time','task_sla',tat,48,'hours','lower_better','BANK-API','system_verified','Workflow turnaround measurement',d),
  (p_tenant,'BANK-KM-001','Kojo Mensah','Credit Officer','Grade 3',p,'KYC','KYC / Site Visit Accuracy','compliance',kyc,100,'percent','higher_better','CHECKLIST','verified','Compliance checklist result',d),
  (p_tenant,'BANK-KM-001','Kojo Mensah','Credit Officer','Grade 3',p,'ATT','Attendance & Punctuality','attendance',att,95,'percent','higher_better','HR-ATT','system_verified','Approved leave excluded from denominator',d)
  on conflict(tenant_id,employee_ref,period_key,fact_code) do update set actual_value=excluded.actual_value,evidence_note=excluded.evidence_note;
  sc:=round(((least(disb/166666.67,1)*25)+(least(3/npl,1)*20)+(least(48/tat,1)*15)+(least(kyc/100,1)*15)+(least(att/95,1)*10)+15)/100*100,1);
  exc:=case when tat>48 then 1 else 0 end;
  insert into hrc_hr_automated_checkins(tenant_id,employee_ref,employee_name,period_key,period_label,prepared_score,status,exception_count,exception_summary)
  values(p_tenant,'BANK-KM-001','Kojo Mensah',p,to_char(d,'FMMonth YYYY'),sc,case when exc>0 then 'exception_review' else 'prepared' end,exc,case when exc>0 then 'Loan turnaround exceeded the 48-hour SLA. Employee/supervisor context requested; all other verified facts require no re-entry.' else 'All verified measures are within expected range. Human input is optional.' end)
  on conflict(tenant_id,employee_ref,period_key) do update set prepared_score=excluded.prepared_score,status=excluded.status,exception_count=excluded.exception_count,exception_summary=excluded.exception_summary;
 end loop;
 return jsonb_build_object('template','BANK-CREDIT-G3','employee','Kojo Mensah','periods',3,'mode','deterministic simulation');
end $$;
grant execute on function unimis.hr_seed_bank_performance_automation(uuid) to authenticated;


-- SOURCE 202610271300_014_performance_setup_templates.sql
-- 014 Performance Setup restructure
alter table unimis.hrc_hr_performance_templates add column if not exists department_id uuid references unimis.hrc_departments(id) on delete set null;
alter table unimis.hrc_hr_performance_templates add column if not exists position_id uuid references unimis.hrc_hr_positions(id) on delete set null;
alter table unimis.hrc_hr_performance_templates add column if not exists grade_id uuid references unimis.hrc_hr_job_grades(id) on delete set null;
alter table unimis.hrc_hr_performance_template_items add column if not exists metric_id uuid references unimis.hrc_hr_performance_metric_library(id) on delete set null;
create unique index if not exists uq_perf_template_metric on unimis.hrc_hr_performance_template_items(template_id,metric_id) where metric_id is not null;
create index if not exists idx_perf_templates_assignment on unimis.hrc_hr_performance_templates(tenant_id,industry,department_id,position_id,grade_id,active);


-- SOURCE 202610271400_015_ai_assisted_performance_data_hub.sql
-- 015 AI-assisted Performance Data Hub
alter table unimis.hrc_hr_performance_metric_library add column if not exists aggregation_method text not null default 'sum'
 check (aggregation_method in ('sum','average','count','latest','min','max'));
alter table unimis.hrc_hr_performance_template_items add column if not exists aggregation_method text not null default 'sum'
 check (aggregation_method in ('sum','average','count','latest','min','max'));

create table if not exists unimis.hrc_hr_performance_mapping_profiles(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 name text not null, source_type text not null default 'csv',
 mapping_config jsonb not null default '{}'::jsonb,
 active boolean not null default true,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(tenant_id,name)
);

create table if not exists unimis.hrc_hr_performance_import_batches(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 file_name text not null, source_type text not null default 'csv',
 mapping_config jsonb not null default '{}'::jsonb,
 total_rows int not null default 0, accepted_rows int not null default 0,
 rejected_rows int not null default 0, duplicate_rows int not null default 0,
 status text not null default 'uploaded', error_summary jsonb not null default '[]'::jsonb,
 created_at timestamptz not null default now(), completed_at timestamptz
);

create table if not exists unimis.hrc_hr_performance_source_records(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 batch_id uuid references unimis.hrc_hr_performance_import_batches(id) on delete set null,
 row_number int, employee_ref text not null, employee_name text,
 observed_at date not null, period_key text not null,
 metric_id uuid references unimis.hrc_hr_performance_metric_library(id) on delete set null,
 metric_code text not null, metric_name text not null,
 raw_column text, raw_value text, numeric_value numeric(18,4), unit text,
 aggregation_method text not null default 'sum',
 verification_status text not null default 'import_validated',
 source_record_key text not null, created_at timestamptz not null default now(),
 unique(tenant_id,source_record_key)
);

do $$ declare t text; begin
 foreach t in array array['hrc_hr_performance_mapping_profiles','hrc_hr_performance_import_batches','hrc_hr_performance_source_records'] loop
  execute format('alter table unimis.%I enable row level security',t);
  execute format('drop policy if exists tenant_member_all on unimis.%I',t);
  execute format('create policy tenant_member_all on unimis.%I for all using (unimis.is_tenant_member(tenant_id)) with check (unimis.is_tenant_member(tenant_id))',t);
 end loop;
end $$;

create index if not exists idx_perf_source_employee_period on unimis.hrc_hr_performance_source_records(tenant_id,employee_ref,period_key,metric_code);
create index if not exists idx_perf_import_batches_created on unimis.hrc_hr_performance_import_batches(tenant_id,created_at desc);

-- Aggregate validated source observations into the existing Performance Ledger.
create or replace function unimis.hr_aggregate_performance_source_records(p_tenant uuid,p_period text)
returns jsonb language plpgsql security definer set search_path=unimis as $$
declare r record; n int:=0; v numeric;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 for r in
  select employee_ref,max(coalesce(employee_name,employee_ref)) employee_name,metric_code,max(metric_name) metric_name,
         max(metric_id::text)::uuid metric_id,max(unit) unit,max(aggregation_method) aggregation_method,
         min(observed_at) first_date,max(observed_at) last_date
  from hrc_hr_performance_source_records
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
  from hrc_hr_performance_source_records
  where tenant_id=p_tenant and period_key=p_period and employee_ref=r.employee_ref and metric_code=r.metric_code and verification_status='import_validated';

  insert into hrc_hr_performance_ledger(tenant_id,employee_ref,employee_name,period_key,fact_code,fact_name,measurement_class,actual_value,target_value,unit,direction,source_code,verification_status,evidence_note,observed_at)
  select p_tenant,r.employee_ref,r.employee_name,p_period,r.metric_code,r.metric_name,
         coalesce(m.measurement_class,'kpi'),v,m.default_target,r.unit,coalesce(m.direction,'higher_better'),
         'CSV-DATA-HUB','system_verified',
         'Aggregated from validated Performance Source Records using '||upper(r.aggregation_method)||'.',r.last_date
  from hrc_hr_performance_metric_library m where m.id=r.metric_id
  on conflict(tenant_id,employee_ref,period_key,fact_code) do update
   set actual_value=excluded.actual_value,verification_status=excluded.verification_status,evidence_note=excluded.evidence_note,observed_at=excluded.observed_at;
  n:=n+1;
 end loop;
 return jsonb_build_object('period',p_period,'ledger_facts',n);
end $$;
grant execute on function unimis.hr_aggregate_performance_source_records(uuid,text) to authenticated;


-- SOURCE 202610271430_016_generated_performance_collection_templates.sql
-- 016 Generated performance data collection templates
create table if not exists unimis.hrc_hr_performance_collection_templates(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 template_token text not null,
 name text not null,
 performance_template_id uuid references unimis.hrc_hr_performance_templates(id) on delete set null,
 period_key text not null,
 frequency text not null default 'monthly',
 employee_count int not null default 0,
 measure_count int not null default 0,
 metadata jsonb not null default '{}'::jsonb,
 active boolean not null default true,
 created_at timestamptz not null default now(),
 unique(tenant_id,template_token)
);
alter table unimis.hrc_hr_performance_collection_templates enable row level security;
drop policy if exists tenant_member_all on unimis.hrc_hr_performance_collection_templates;
create policy tenant_member_all on unimis.hrc_hr_performance_collection_templates for all
 using (unimis.is_tenant_member(tenant_id)) with check (unimis.is_tenant_member(tenant_id));
create index if not exists idx_perf_collection_template_lookup
 on unimis.hrc_hr_performance_collection_templates(tenant_id,period_key,performance_template_id,active);


-- UNIMIS HRPAYROLLCORE BRIDGE 171
create or replace function unimis.unimis_hrpayroll_context167()
returns table(tenant_id uuid,institution_name text,institution_code text,hr_role text)
language plpgsql security definer set search_path=unimis as $$
declare v_inst uuid; v_name text; v_code text; v_role text; v_hr_role text;
begin
 select m.institution_id,i.name,i.code,r.code into v_inst,v_name,v_code,v_role
 from unimis.unimis_effective_memberships116 m
 join unimis.institutions i on i.id=m.institution_id
 join unimis.roles r on r.id=m.role_id
 where m.user_id=auth.uid() and m.status='active' and r.is_active
 order by m.is_primary desc limit 1;
 if v_inst is null then return; end if;
 v_hr_role:=case
  when v_role='owner' then 'owner'
  when v_role in ('admin','administrator','registrar') then 'administrator'
  when v_role in ('hr_manager','hr_officer') then v_role
  when v_role in ('payroll_manager','payroll_officer') then v_role
  when v_role in ('finance_officer','accountant') then 'finance_manager'
  when v_role='auditor' then 'auditor'
  else 'employee' end;
 insert into unimis.hrc_tenants(id,name,code,hr_enabled,payroll_enabled,created_by)
 values(v_inst,v_name,coalesce(nullif(v_code,''),'UNI-'||left(v_inst::text,8)),true,true,auth.uid())
 on conflict(id) do update set name=excluded.name,hr_enabled=true,payroll_enabled=true;
 insert into unimis.hrc_tenant_memberships(tenant_id,user_id,role,status)
 values(v_inst,auth.uid(),v_hr_role,'active')
 on conflict(tenant_id,user_id) do update set role=excluded.role,status='active';
 return query select v_inst,v_name,v_code,case when v_role in ('finance_officer','accountant') then 'accountant' else v_hr_role end;
end $$;
grant execute on function unimis.unimis_hrpayroll_context167() to authenticated;


-- Refresh Supabase/PostgREST schema cache after this stage.
NOTIFY pgrst, 'reload schema';
