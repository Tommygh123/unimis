-- 011r: continue an existing scheduled check-in instead of trying to create a duplicate period.
-- One scheduled check-in is the parent record; KPI results/evidence are added or updated beneath it.
-- Already verified/system-verified facts are preserved. ADHOC check-ins remain repeatable.

create or replace function public.hr_performance_record_period_checkin(
 p_tenant uuid,p_review uuid,p_period_key text,p_period_label text,p_period_start date,p_period_end date,p_checkin_date date,
 p_status text,p_actual_progress text,p_achievements text,p_blockers text,p_evidence text,p_support_required text,p_next_actions text,p_measures jsonb
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_checkin uuid; v_existing_item uuid; v_existing_verification text; m jsonb; v_item uuid; v_actual numeric; v_progress numeric; v_reviewer uuid; v_type text; v_source text; v_verification text; v_reused boolean:=false;
begin
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select reviewer_employee_id into v_reviewer from hr_performance_reviews where tenant_id=p_tenant and id=p_review and plan_status='activated' and coalesce(finalization_status,'draft')<>'finalized';
 if not found then raise exception 'Review must be activated and not finalized'; end if;
 if coalesce(trim(p_period_key),'')='' then raise exception 'Check-in period is required'; end if;
 if p_period_start is not null and p_period_end is not null and p_period_end<p_period_start then raise exception 'Check-in period end date cannot be before its start date'; end if;
 if p_status not in ('on_track','at_risk','off_track','exceeded') then raise exception 'Invalid check-in status'; end if;
 if upper(p_period_key)<>'ADHOC' then
  select id into v_checkin from hr_performance_checkins
   where tenant_id=p_tenant and review_id=p_review and period_key=p_period_key
   order by created_at asc limit 1;
 end if;
 if v_checkin is null then
  insert into hr_performance_checkins(tenant_id,review_id,checkin_date,period_key,period_label,period_start,period_end,reviewer_employee_id,progress_percent,status,actual_progress,achievements,blockers,evidence,support_required,next_actions)
  values(p_tenant,p_review,coalesce(p_checkin_date,current_date),p_period_key,coalesce(nullif(trim(p_period_label),''),p_period_key),p_period_start,p_period_end,v_reviewer,null,p_status,nullif(trim(p_actual_progress),''),nullif(trim(p_achievements),''),nullif(trim(p_blockers),''),nullif(trim(p_evidence),''),nullif(trim(p_support_required),''),nullif(trim(p_next_actions),'')) returning id into v_checkin;
 else
  v_reused:=true;
  update hr_performance_checkins set
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
   from hr_performance_plan_items pi left join hr_performance_metric_library ml on ml.id=pi.metric_id
   where pi.id=v_item and pi.tenant_id=p_tenant and pi.review_id=p_review;
   if not found then raise exception 'Invalid performance measure in check-in'; end if;
   v_verification=case when v_type='system_calculated' then 'system_verified' when v_type='behavioral_rubric' then 'manager_attested' else 'pending' end;
   if v_verification='pending' and coalesce(trim(m->>'evidence'),'')='' and not exists(select 1 from hr_performance_evidence_attachments a where a.tenant_id=p_tenant and a.review_id=p_review and a.plan_item_id=v_item) then
    raise exception 'Objective/manual source figures require evidence before submission';
   end if;
   v_existing_item:=null; v_existing_verification:=null;
   select id,verification_status into v_existing_item,v_existing_verification
    from hr_performance_checkin_items where tenant_id=p_tenant and checkin_id=v_checkin and plan_item_id=v_item
    order by created_at desc limit 1;
   if v_existing_item is null then
    insert into hr_performance_checkin_items(tenant_id,checkin_id,review_id,plan_item_id,actual_value,evidence,evidence_source,measurement_inputs,measurement_type,verification_status)
    values(p_tenant,v_checkin,p_review,v_item,v_actual,nullif(trim(m->>'evidence'),''),coalesce(nullif(m->>'evidence_source',''),case when v_source='operational_record' then 'system_record' else 'manager_observation' end),coalesce(m->'measurement_inputs','{}'::jsonb),v_type,v_verification);
   elsif v_existing_verification in ('verified','system_verified') then
    null; -- preserve already verified facts; continuing the check-in must never overwrite them
   else
    update hr_performance_checkin_items set actual_value=v_actual,evidence=nullif(trim(m->>'evidence'),''),
     evidence_source=coalesce(nullif(m->>'evidence_source',''),case when v_source='operational_record' then 'system_record' else 'manager_observation' end),
     measurement_inputs=coalesce(m->'measurement_inputs','{}'::jsonb),measurement_type=v_type,verification_status=v_verification,verified_by=null,verified_at=null,verification_note=null
    where id=v_existing_item;
   end if;
  end if;
 end loop;
 perform public.hr_performance_refresh_intelligence(p_tenant,p_review);
 select case when coalesce(sum(weight) filter(where system_score is not null),0)=0 then null else round(sum(system_score*weight) filter(where system_score is not null)/sum(weight) filter(where system_score is not null),2) end into v_progress from hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review;
 perform public.hr_refresh_checkin_verified_progress(p_tenant,v_checkin);
 update hr_performance_checkins set progress_percent=current_verified_progress_percent, recorded_progress_percent=current_verified_progress_percent where id=v_checkin;
 select current_verified_progress_percent into v_progress from hr_performance_checkins where id=v_checkin;
 return jsonb_build_object('checkin_id',v_checkin,'progress_percent',v_progress,'period',p_period_label,'verification_required',true,'reused_existing',v_reused);
end $$;
grant execute on function public.hr_performance_record_period_checkin(uuid,uuid,text,text,date,date,date,text,text,text,text,text,text,text,jsonb) to authenticated;
