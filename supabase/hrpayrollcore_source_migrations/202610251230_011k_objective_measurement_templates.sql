-- 011k: objective measurement templates, frozen activated-plan definitions, and check-in input audit trail.
alter table public.hr_performance_metric_library
 add column if not exists formula_config jsonb not null default '{}'::jsonb;

alter table public.hr_performance_plan_items
 add column if not exists measurement_type_snapshot text,
 add column if not exists data_source_snapshot text,
 add column if not exists measurement_method_snapshot text,
 add column if not exists rubric_snapshot jsonb,
 add column if not exists checklist_snapshot jsonb,
 add column if not exists formula_config_snapshot jsonb,
 add column if not exists evidence_required_snapshot boolean,
 add column if not exists evidence_min_count_snapshot integer;

alter table public.hr_performance_checkin_items
 add column if not exists measurement_inputs jsonb not null default '{}'::jsonb,
 add column if not exists measurement_type text;

-- Starter objective definitions. Administrators remain free to edit these in KPI Library before future plans are activated.
update public.hr_performance_metric_library
set measurement_type='formula',data_source='operational_record',unit='percent',
 measurement_method='Accuracy % = acceptable/correct work items divided by total work items reviewed × 100. Use a QA, inspection, transaction or rework record as evidence.',
 formula_config='{"numerator_label":"Acceptable / correct work items","denominator_label":"Total work items reviewed"}'::jsonb,
 evidence_required=true,evidence_min_count=1
where lower(name) like '%operational work quality%accuracy%';

update public.hr_performance_metric_library
set measurement_type='behavioral_rubric',data_source='manager_verified',unit='score',
 measurement_method='Select the teamwork/collaboration behaviour best supported by documented observations and evidence.',
 rubric='[{"score":1,"label":"Unsatisfactory","anchor":"Frequently undermines teamwork, communication or accountability and requires repeated intervention."},{"score":2,"label":"Needs improvement","anchor":"Inconsistent collaboration or communication causes avoidable friction or follow-up."},{"score":3,"label":"Meets expectations","anchor":"Works cooperatively, communicates appropriately and accepts normal accountability."},{"score":4,"label":"Exceeds expectations","anchor":"Consistently collaborates well, communicates proactively and supports team delivery."},{"score":5,"label":"Exceptional","anchor":"Models outstanding collaboration, resolves issues constructively and materially improves team effectiveness."}]'::jsonb,
 evidence_required=true,evidence_min_count=1
where lower(name) like '%operational collaboration%conduct%';

update public.hr_performance_metric_library
set measurement_type='compliance_checklist',data_source='manager_verified',unit='percent',
 measurement_method='Assess applicable SOP/control requirements as Compliant, Partially compliant, Non-compliant or N/A. The system calculates the percentage from applicable items.',
 checklist='[{"label":"Follows documented SOP steps for assigned work"},{"label":"Completes required records/documentation"},{"label":"Observes approval and control requirements"},{"label":"Escalates exceptions or deviations appropriately"},{"label":"Closes corrective actions within agreed timelines"}]'::jsonb,
 evidence_required=true,evidence_min_count=1
where lower(name) like '%responsibility%sop%execution%';

update public.hr_performance_metric_library
set measurement_type='formula',data_source='operational_record',unit='percent',
 measurement_method='Achievement % = completed/achieved agreed outputs divided by total agreed outputs due for the review period × 100. The underlying deliverables must be evidenced.',
 formula_config='{"numerator_label":"Outputs / milestones achieved","denominator_label":"Outputs / milestones due"}'::jsonb,
 evidence_required=true,evidence_min_count=1
where lower(name) like '%target%output%achievement%';

-- Freeze measurement definitions into every currently activated plan after the corrected starter definitions above.
update public.hr_performance_plan_items pi set
 measurement_type_snapshot=m.measurement_type,
 data_source_snapshot=m.data_source,
 measurement_method_snapshot=m.measurement_method,
 rubric_snapshot=m.rubric,
 checklist_snapshot=m.checklist,
 formula_config_snapshot=m.formula_config,
 evidence_required_snapshot=m.evidence_required,
 evidence_min_count_snapshot=m.evidence_min_count
from public.hr_performance_metric_library m, public.hr_performance_reviews r
where pi.metric_id=m.id and pi.review_id=r.id and r.plan_status='activated';

create or replace function public.hr_snapshot_performance_measurements_on_activation() returns trigger
language plpgsql security definer set search_path=public as $$
begin
 if new.plan_status='activated' and coalesce(old.plan_status,'')<>'activated' then
  update public.hr_performance_plan_items pi set
   measurement_type_snapshot=m.measurement_type,
   data_source_snapshot=m.data_source,
   measurement_method_snapshot=m.measurement_method,
   rubric_snapshot=m.rubric,
   checklist_snapshot=m.checklist,
   formula_config_snapshot=m.formula_config,
   evidence_required_snapshot=m.evidence_required,
   evidence_min_count_snapshot=m.evidence_min_count
  from public.hr_performance_metric_library m
  where pi.review_id=new.id and pi.tenant_id=new.tenant_id and pi.metric_id=m.id;
 end if;
 return new;
end $$;
drop trigger if exists trg_hr_snapshot_performance_measurements_on_activation on public.hr_performance_reviews;
create trigger trg_hr_snapshot_performance_measurements_on_activation after update of plan_status on public.hr_performance_reviews for each row execute function public.hr_snapshot_performance_measurements_on_activation();

create or replace function public.hr_performance_record_period_checkin(
 p_tenant uuid,p_review uuid,p_period_key text,p_period_label text,p_period_start date,p_period_end date,p_checkin_date date,
 p_status text,p_actual_progress text,p_achievements text,p_blockers text,p_evidence text,p_support_required text,p_next_actions text,p_measures jsonb
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_checkin uuid; m jsonb; v_item uuid; v_actual numeric; v_progress numeric; v_reviewer uuid; v_type text;
begin
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select reviewer_employee_id into v_reviewer from hr_performance_reviews where tenant_id=p_tenant and id=p_review and plan_status='activated' and coalesce(finalization_status,'draft')<>'finalized';
 if not found then raise exception 'Review must be activated and not finalized'; end if;
 if coalesce(trim(p_period_key),'')='' then raise exception 'Check-in period is required'; end if;
 if p_period_start is not null and p_period_end is not null and p_period_end<p_period_start then raise exception 'Check-in period end date cannot be before its start date'; end if;
 if p_status not in ('on_track','at_risk','off_track','exceeded') then raise exception 'Invalid check-in status'; end if;
 insert into hr_performance_checkins(tenant_id,review_id,checkin_date,period_key,period_label,period_start,period_end,reviewer_employee_id,progress_percent,status,actual_progress,achievements,blockers,evidence,support_required,next_actions)
 values(p_tenant,p_review,coalesce(p_checkin_date,current_date),p_period_key,coalesce(nullif(trim(p_period_label),''),p_period_key),p_period_start,p_period_end,v_reviewer,null,p_status,nullif(trim(p_actual_progress),''),nullif(trim(p_achievements),''),nullif(trim(p_blockers),''),nullif(trim(p_evidence),''),nullif(trim(p_support_required),''),nullif(trim(p_next_actions),'')) returning id into v_checkin;
 for m in select * from jsonb_array_elements(coalesce(p_measures,'[]'::jsonb)) loop
  v_item=nullif(m->>'item_id','')::uuid; v_actual=nullif(m->>'actual_value','')::numeric;
  if v_item is not null and v_actual is not null then
   select coalesce(pi.measurement_type_snapshot,ml.measurement_type,'numeric') into v_type
   from hr_performance_plan_items pi left join hr_performance_metric_library ml on ml.id=pi.metric_id
   where pi.id=v_item and pi.tenant_id=p_tenant and pi.review_id=p_review;
   if not found then raise exception 'Invalid performance measure in check-in'; end if;
   insert into hr_performance_checkin_items(tenant_id,checkin_id,review_id,plan_item_id,actual_value,evidence,evidence_source,measurement_inputs,measurement_type)
   values(p_tenant,v_checkin,p_review,v_item,v_actual,nullif(trim(m->>'evidence'),''),coalesce(nullif(m->>'evidence_source',''),'manager_observation'),coalesce(m->'measurement_inputs','{}'::jsonb),v_type);
  end if;
 end loop;
 perform public.hr_performance_refresh_intelligence(p_tenant,p_review);
 select case when coalesce(sum(weight) filter (where system_score is not null),0)=0 then null else round(sum(system_score*weight) filter (where system_score is not null)/sum(weight) filter (where system_score is not null),2) end
 into v_progress from hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review;
 update hr_performance_checkins set progress_percent=v_progress where id=v_checkin;
 return jsonb_build_object('checkin_id',v_checkin,'progress_percent',v_progress,'period',p_period_label);
end $$;
grant execute on function public.hr_performance_record_period_checkin(uuid,uuid,text,text,date,date,date,text,text,text,text,text,text,text,jsonb) to authenticated;
